# 09. Machine Configuration Language (MCL)

## Origin & Rationale

In traditional xv6-riscv, machine and memory initialization is handled imperatively in C:

```c
kinit();        // Sets up the free physical frame list from `end` to PHYSTOP
kvminit();      // Allocates root and intermediate page tables via kalloc() and runs mappages() loops
kvminithart();  // Writes root page table address into satp, executes sfence.vma
```

This traditional pattern suffers from several verification and engineering challenges:
1. **Dynamic Boot Allocation Loops**: Building the kernel's initial page tables requires a working heap/frame allocator (`kalloc()`) before paging is even enabled.
2. **Runtime Pointer Traversal**: The iterative `walk()` function dynamically creates intermediate page table pages, which can fail at runtime due to out-of-memory conditions.
3. **Implicit Invariants**: Security invariants such as $W \oplus X$ (Write-xor-Execute) and kernel isolation (no user access to MMIO or kernel memory) must be verified through complex Hoare-logic proofs over imperative C pointer loops.

Instead of writing imperative boot code, we recognize hardware initialization as a **Machine Configuration Language (MCL)**.

---

## Architecture: Declarative Machine Configuration

The MCL treats the machine topology, memory map, and boot page tables as a purely declarative specification evaluated at Lean 4 compile time:

```
+-----------------------------------------------------------+
|              Declarative MachineConfig                     |
|  (RAM Base/Size, UART0, VirtIO, PLIC, Text, RAM Pool, ...) |
+-----------------------------------------------------------+
                             |
       +---------------------+---------------------+
       |                                           |
       v                                           v
+-------------------------------+       +-------------------------------+
|  Compile-Time Invariant Proofs|       |  Deterministic Tree Compiler  |
|  - W-xor-X (decide)           |       |  - 2MB Megapages for RAM      |
|  - Kernel Isolation (decide)  |       |  - 4KB Leaves for Devices     |
|  - 4KB Page Alignment (decide)|       |  - Output: 7 Static Tables    |
+-------------------------------+       +-------------------------------+
                                                   |
                                                   v
                                        +-------------------------------+
                                        |    Static Assembly Emission   |
                                        |  - .section .data, .align 12  |
                                        |  - .quad PTE literals         |
                                        +-------------------------------+
                                                   |
                                                   v
                                        +-------------------------------+
                                        |    Supervisor satp Enable     |
                                        |  - (8 << 60) | (boot_l2 >> 12)|
                                        |  - sfence.vma TLB flush       |
                                        +-------------------------------+
```

---

## Core Constructs

### 1. Permissions & Mappings
Memory permissions are modeled as an algebraic data type:
```lean
inductive Perm where
  | none | r | rw | rx | rwx
```
Each mapped hardware or memory region is defined as a typed record:
```lean
structure Mapping where
  name   : String
  va     : UInt64
  pa     : UInt64
  size   : UInt64
  perms  : Perm
  user   : Bool := false
  global : Bool := true
```

### 2. Concrete Machine Map (`qemuVirtConfig`)
The default QEMU RISC-V `virt` board configuration is declared as a constant value:
- **UART0**: `0x10000000` (4KB, RW)
- **VirtIO Disk**: `0x10001000` (4KB, RW)
- **PLIC (Interrupt Controller)**: `0x0c000000` (4MB, RW)
- **Test Finisher / Poweroff**: `0x00100000` (4KB, RW)
- **Kernel Text**: `0x80000000` (2MB, RX, strictly non-writable)
- **Kernel Data & Free RAM**: `0x80200000..0x88000000` (126MB, RW, strictly non-executable)
- **Trampoline**: `0x3ffffff000` (4KB, RX, strictly non-writable)

---

## Compile-Time Verified Invariants

Before any code is generated or linked, Lean 4 verifies the machine security invariants at compile time:

```lean
-- 1. Strict W-xor-X: No mapping is both writable and executable
theorem qemuVirt_satisfies_WX : satisfiesWX qemuVirtConfig = true := by decide

-- 2. Kernel Isolation: No user privileges on any kernel or MMIO mapping
theorem qemuVirt_is_isolated : kernelIsolated qemuVirtConfig = true := by decide

-- 3. Alignment: All VAs, PAs, and sizes are 4096-byte aligned
theorem qemuVirt_aligned : allPageAligned qemuVirtConfig = true := by decide

-- 4. Leaf Page Invariants: Kernel text is executable; RAM and PLIC are writable
theorem virtPageTables_text_rx : ... = true := by rfl
theorem virtPageTables_ram_rw  : ... = true := by decide
theorem virtPageTables_plic_rw : ... = true := by rfl
```

If an engineer introduces a mapping violating $W \oplus X$ (e.g. mapping kernel data as executable), compilation fails with a proof error before the kernel ELF can ever be built.

---

## Compile-Time Sv39 Tree Compiler & Emission

The MCL tree compiler generates the exact 7 page tables needed for the initial Sv39 hierarchy (28 KB):
1. `boot_l2`: Root Level 2 table.
2. `boot_l1_0`: Level 1 intermediate table for MMIO (`0x00000000..0x3fffffff`).
3. `boot_l1_2`: Level 1 intermediate table for RAM (`0x80000000..0xbfffffff`).
4. `boot_l0_low`: Level 0 leaf table for QEMU test finisher (`0x100000`).
5. `boot_l0_mmio`: Level 0 leaf table for UART0 and VirtIO0.
6. `boot_l1_511`: Level 1 table for top 1GB (`0x3fc0000000..0x3fffffffff`).
7. `boot_l0_tramp`: Level 0 leaf table for Trampoline (`0x3ffffff000`).

RAM is mapped with 2MB megapages in Level 1 (1 megapage for text, 63 megapages for data/free memory), eliminating the need for 64 Level 0 page tables.

Tables are emitted directly into `.data` with `.align 12` and `.quad` PTE literals:
```assembly
.section .data
.align 12
.globl boot_l2
boot_l2:
    # Sv39 Level 2 Page Table: boot_l2
    .quad 0
    ...
```

---

## Hardware MMU Activation

In Supervisor mode (`main`), the `enablePaging` DSL command links the table hierarchy, writes `satp`, and executes `sfence.vma`:

```lean
function main := do
  uartPrint "\n=== xv6-lean: Booted into Supervisor mode! ===\n"

  -- Activate Sv39 MMU Paging using declarative Machine Configuration (MCL)
  enablePaging "boot_l2"

  uartPrint "=== xv6-lean: MMU Sv39 paging enabled successfully via MCL static tables! ===\n\n"
```

Because the kernel text and MMIO devices are identity-mapped in virtual address space, the instruction pointer (`PC`) and memory writes continue without interruption after `satp` is written and TLB entries are flushed with `sfence.vma`.
