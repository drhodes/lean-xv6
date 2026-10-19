# From Zero to User-Mode Shell: Building a Formally Specified xv6 in Lean 4

**By the lean-xv6 Engineering Team**  
*Target Architecture: RISC-V 64-bit (RV64GC) | Language: Lean 4 | Verification: libspec + Lean Kernel*

---

## Abstract

Operating systems have historically been written in C, accepting null pointer dereferences, data races, and unverified memory mappings as an unavoidable cost of bare-metal control. In this project, we re-engineer the MIT xv6-riscv kernel from the ground up using **Lean 4**—a pure functional language with dependent types, a native macro system, and an interactive theorem prover.

Starting from bare QEMU virt hardware at `0x80000000` in Machine Mode, we construct a fully functional operating system that boots into Supervisor Mode, proves and activates Sv39 virtual memory, implements physical memory allocation and context-switched process scheduling, transitions across the supervisor/user privilege boundary via an isolated trampoline page, and executes an interactive minimal shell in **User Mode (Ring 3)** backed by POSIX-compatible console I/O system calls.

This article details the five architectural phases that carried us from zero to a live, interactive shell prompt.

```mermaid
flowchart TD
    subgraph Phase1["Part 1: The Lean 4 Machine DSL"]
        M1["Monadic AsmM Monad"] --> M2["Instruction AST & Reg Types"]
        M2 --> M3["Stage W Calling Convention"]
    end

    subgraph Phase2["Part 2: MCL & Compile-Time Paging"]
        P1["Declarative MachineConfig"] --> P2["Compile-Time Theorems (W⊕X)"]
        P2 --> P3["Sv39 Static Page Table Compiler"]
    end

    subgraph Phase3["Part 3: Memory & Concurrency"]
        C1["kinit / kalloc / kfree Allocator"] --> C2["struct proc & Table (64 slots)"]
        C2 --> C3["swtch Callee-Saved Context Switch"]
    end

    subgraph Phase4["Part 4: Ring 3 Privilege Chasm"]
        U1["Dual-Mapped Trampoline (0x3ffffff000)"] --> U2["Sv39 User Page Tables (W⊕X)"]
        U2 --> U3["usertrapret -> sret -> User Mode"]
    end

    subgraph Phase5["Part 5: Syscalls & Interactive Shell"]
        S1["UART0 Polled Console Driver"] --> S2["Syscall Dispatcher (ecall)"]
        S2 --> S3["Ring 3 User Shell (help, info, echo, exit)"]
    end

    Phase1 --> Phase2
    Phase2 --> Phase3
    Phase3 --> Phase4
    Phase4 --> Phase5
```

---

# Part 1: The Vision — A Domain-Specific Architecture in Lean 4

The foundational challenge of writing an operating system in a theorem prover is bridging the semantic gap between high-level functional abstractions and the raw registers of bare-metal silicon. Rather than using external inline assembly strings or C stubs, we designed an embedded monadic domain-specific language (DSL) directly within Lean 4.

### 1.1 The Monadic Assembly Builder (`AsmM`)

The core assembler is represented as a state monad `AsmM` accumulating strongly typed assembly AST items:

```lean
-- LeanXv6/RiscV.lean
inductive Reg where
  | zero | ra | sp | gp | tp | t0 | t1 | t2
  | s0   | s1 | a0 | a1 | a2 | a3 | a4 | a5
  | a6   | a7 | s2 | s3 | s4 | s5 | s6 | s7
  | s8   | s9 | s10 | s11 | t3 | t4 | t5 | t6
  deriving Repr, DecidableEq, Inhabited

inductive Instr where
  | add   (rd rs1 rs2 : Reg)
  | addi  (rd rs1 : Reg) (imm : Int)
  | ld    (rd : Reg) (offset : Int) (base : Reg)
  | sd    (rs : Reg) (offset : Int) (base : Reg)
  | ecall
  | sret
  | csrrw (rd : Reg) (csr : CSR) (rs : Reg)
  | lla   (rd : Reg) (sym : String)
  -- Full RV64GC instruction catalog...
```

The monad provides hygienic assembly construction where labels are guaranteed unique, immediate values are validated against bit-widths, and machine registers are compile-time constants.

### 1.2 Stage W: Low IR Functions & Calling Conventions

Writing low-level kernel routines in bare assembly quickly leads to register clobbering and stack corruption. We introduced **Stage W**: a declarative function abstraction that automatically handles:
- RISC-V standard ABI argument binding (`a0` through `a7`).
- 16-byte stack frame alignment.
- Callee-saved register spilling in prologues and restoration in epilogues.

```lean
-- Declarative syntax for verified kernel routines
fn kernelAdd (x y) [ra s0] := do
  add s0 x y
  uartPrint "=== Stage W function (kernelAdd) executed successfully! ===\n"
  returnVal s0
```

When compiled, the macro calculates exact stack requirements `((slots * 8 + 15) / 16) * 16`, emits the prologue `addi sp, sp, -32; sd ra, 0(sp); sd s0, 8(sp)`, preserves callee registers, and generates the matching epilogue with `ret`.

---

# Part 2: Machine Configuration Language (MCL) & Compile-Time Paging

In standard MIT xv6, page tables are created imperatively at runtime. The kernel executes C functions (`kinit`, `kvminit`, `walk`) that allocate 4KB physical pages and mutate pointers on the heap. If a page fault or misalignment occurs, debugging is notoriously difficult.

In `lean-xv6`, we inverted this paradigm with the **Machine Configuration Language (MCL)**: the entire hardware memory topology and root Sv39 page tables are computed, validated against mathematical security theorems, and emitted as static read-only tables at compile time.

```
       Sv39 39-Bit Virtual Address Space
+-------------------------------------------------------+ 0x3ffffff000 (MAXVA - 4KB)
| Trampoline Page (PTE_V | PTE_R | PTE_X | PTE_G)       |
+-------------------------------------------------------+ 0x3fffffe000 (MAXVA - 8KB)
| User Trapframe Page (PTE_V | PTE_R | PTE_W)           |
+-------------------------------------------------------+
| ... Unmapped High Virtual Memory Guard Space ...      |
+-------------------------------------------------------+ 0x88000000 (PHYSTOP)
| Kernel RAM Mapping (PTE_V | PTE_R | PTE_W)            |
+-------------------------------------------------------+ 0x80000000 (KERNBASE)
| Kernel Code & Rodata (PTE_V | PTE_R | PTE_X)          |
+-------------------------------------------------------+ 0x10000000
| MMIO Devices: UART0 (0x10000000), VirtIO (0x10001000)  |
+-------------------------------------------------------+ 0x00000000
| User Virtual Address Space (Page 0 Code, Page 1 Data) |
+-------------------------------------------------------+
```

### 2.1 Formal Security Proofs in Lean

We declare our hardware configuration as a pure data structure:

```lean
-- LeanXv6/MachineConfig.lean
def qemuVirtConfig : MachineConfig := {
  regions := [
    { name := "qemu_test", va := 0x100000,   pa := 0x100000,   size := 0x1000,    perm := .readWrite },
    { name := "plic",      va := 0x0c000000, pa := 0x0c000000, size := 0x400000,  perm := .readWrite },
    { name := "uart0",     va := 0x10000000, pa := 0x10000000, size := 0x1000,    perm := .readWrite },
    { name := "virtio0",   va := 0x10001000, pa := 0x10001000, size := 0x1000,    perm := .readWrite },
    { name := "kernel_rx", va := 0x80000000, pa := 0x80000000, size := 0x200000,  perm := .readExec },
    { name := "kernel_rw", va := 0x80200000, pa := 0x80200000, size := 0x7e00000, perm := .readWrite },
    { name := "tramp",     va := 0x3ffffff000, pa := 0x80010000, size := 0x1000,  perm := .readExec }
  ]
}
```

Before a single assembly instruction is emitted, Lean's typechecker verifies critical security properties:

```lean
-- 1. Strict W ⊕ X: No region is simultaneously writable and executable
theorem qemuVirt_satisfies_WX : satisfiesWX qemuVirtConfig = true := by decide

-- 2. Kernel Isolation: No supervisor page leaks user privilege
theorem qemuVirt_is_isolated : kernelIsolated qemuVirtConfig = true := by decide

-- 3. Hardware Alignment: All addresses are strictly 4096-byte page aligned
theorem qemuVirt_aligned : allPageAligned qemuVirtConfig = true := by decide
```

### 2.2 The Trampoline VPN[2] Mathematical Fix

During implementation of Sv39 Level 2 routing for the Trampoline at `0x3ffffff000` (`MAXVA - 4KB`), traditional codebases frequently hardcode index `511`. However, calculating the actual RISC-V Sv39 Virtual Page Number Level 2:

$$\text{VPN}[2] = \left(\frac{\text{0x3ffffff000}}{2^{30}}\right) \ \& \ \text{0x1ff} = \left(\frac{\text{0x3ffffff000}}{\text{0x40000000}}\right) \ \& \ \text{0x1ff} = 255 \ (\text{0x0ff})$$

Because bits 38:30 of `0x3ffffff000` evaluate to `255`, mapping index 511 leaves the top page table unlinked, triggering instant unhandled page faults. MCL detected this mapping discrepancy at compile time, generating exact table entries for `boot_l2[255]`.

---

# Part 3: Kernel Allocator & Preemptive Concurrency

With paging active, the kernel transitions to dynamic physical page allocation and process concurrency.

### 3.1 The Physical Page Allocator (`kalloc` & `kfree`)

Our memory allocator manages physical memory between the linker symbol `end` and `PHYSTOP` (`0x88000000`, 128MB). It employs an embedded free-list: each free 4096-byte page stores the 64-bit pointer to the next free page at offset `0`.

```lean
-- LeanXv6/Kalloc.lean
fn kfree (pa) [ra s0] := do
  mv s0 pa
  -- Scrub page with sentinel byte 1 to catch dangling pointers
  callFn memset [s0, 1, 4096]
  -- Link into freelist: *pa = kmem_freelist; kmem_freelist = pa
  la t0 kmem_freelist
  ld t1 0 t0
  sd t1 0 s0
  sd s0 0 t0

fn kalloc () [ra s0] := do
  la t0 kmem_freelist
  ld s0 0 t0
  beqz s0 "kalloc_out_of_mem"
  -- Pop page: kmem_freelist = next
  ld t1 0 s0
  sd t1 0 t0
  -- Scrub page with sentinel byte 2
  callFn memset [s0, 2, 4096]
  returnVal s0
```

### 3.2 Process Table and Low-Level Context Switch (`swtch`)

We declare a static table of 64 `struct proc` entries (`procTable`). Each process controls:
- State (`UNUSED`, `USED`, `SLEEPING`, `RUNNABLE`, `RUNNING`, `ZOMBIE`).
- A dedicated 4KB kernel stack (`kstack`).
- An isolated physical `trapframe` page.
- Sv39 user root page table (`pagetable`).
- User physical page records (`user_code_pa`, `user_stack_pa`).

```
                struct proc Layout (208 bytes)
+--------+--------+--------+--------+-------------+-------------+
| State  |  PID   | Kstack | Trapfr | UserCode PA | UserStk PA  |
| 8 bytes| 8 bytes| 8 bytes| 8 bytes|   8 bytes   |   8 bytes   |
+--------+--------+--------+--------+-------------+-------------+
```

Context switching between execution threads is implemented by `swtch`, saving and restoring the callee-saved register set (`ra`, `sp`, `s0..s11`):

```lean
-- LeanXv6/Proc.lean
function swtch := do
  -- a0 = old thread context*, a1 = new thread context*
  sd ra  0 a0;  sd sp  8 a0
  sd s0 16 a0;  sd s1 24 a0;  sd s2 32 a0;  sd s3 40 a0
  sd s4 48 a0;  sd s5 56 a0;  sd s6 64 a0;  sd s7 72 a0
  sd s8 80 a0;  sd s9 88 a0;  sd s10 96 a0; sd s11 104 a0

  ld ra  0 a1;  ld sp  8 a1
  ld s0 16 a1;  ld s1 24 a1;  ld s2 32 a1;  ld s3 40 a1
  ld s4 48 a1;  ld s5 56 a1;  ld s6 64 a1;  ld s7 72 a1
  ld s8 80 a1;  ld s9 88 a1;  ld s10 96 a1; ld s11 104 a1
  ret
```

---

# Part 4: Crossing the Ring 0 $\to$ Ring 3 Privilege Boundary

The central milestone of kernel development is dropping CPU privilege to Ring 3 (User Mode) while maintaining full control over exceptions and interrupts.

```mermaid
sequenceDiagram
    autonumber
    actor U as User Mode (Ring 3)
    participant T as Trampoline (uservec / userret)
    participant K as Supervisor Kernel (usertrap)
    participant S as Syscall Dispatcher

    Note over K: usertrapret() prepares trapframe & stvec
    K->>T: jr userret (a0=TRAPFRAME, a1=user_satp)
    Note over T: Switch satp to User PT<br/>Restore user registers<br/>csrrw a0, sscratch, a0
    T->>U: sret (Drops privilege to U-mode, PC=0x00000000)

    Note over U: Shell executes instructions<br/>Prepares a7=SYS_read, a0=0, a1=0x1000<br/>Executes ecall
    U->>T: Hardware Trap to stvec (uservec)
    Note over T: csrrw a0, sscratch, a0<br/>Save all 31 registers<br/>Switch satp to Kernel PT
    T->>K: jr usertrap
    K->>S: syscall(p)
    Note over S: uva2pa() translates 0x1000<br/>sys_read() polls UART0<br/>Stores result in trapframe->a0
    S-->>K: return 0 (continue)
    K->>T: call usertrapret
    T->>U: sret (Resumes User Shell at PC+4)
```

### 4.1 The Dual-Mapped Trampoline Page

When the CPU drops privilege, the page table in register `satp` is swapped from the kernel's address space to the user's isolated address space. The code executing this transition must exist at the **exact same virtual address in both page tables**.

We place `uservec` and `userret` in a dedicated ELF section `trampsec` mapped at `0x3ffffff000`:
- In the kernel: `boot_l2[255]` points to `boot_l1_511[511]` pointing to physical `0x80010000`.
- In each user process: `proc_pagetable` maps `0x3ffffff000` to physical `0x80010000` with permissions `PTE_V | PTE_R | PTE_X | PTE_G`.

### 4.2 Register Preservation via `sscratch`

When transitioning from User Mode into Supervisor Mode via `ecall`, all 31 user registers contain live user application state. How can the kernel save them without corrupting a single register?

The RISC-V architecture provides the supervisor scratch register `sscratch`. In `userret`, the kernel places the virtual address of the process trapframe (`0x3fffffe000`) into `sscratch`. When a trap occurs, `uservec` begins:

```assembly
# LeanXv6/User.lean: uservec
uservec:
    # Atomic exchange: a0 becomes TRAPFRAME_VA, sscratch stores user a0!
    csrrw a0, sscratch, a0

    # Save user registers into trapframe
    sd ra, 40(a0)
    sd sp, 48(a0)
    sd gp, 56(a0)
    sd tp, 64(a0)
    sd t0, 72(a0)
    # ... save t1..t6, s0..s11, a1..a7 ...

    # Read user's original a0 from sscratch and save it
    csrr t0, sscratch
    sd t0, 112(a0)

    # Restore kernel context (satp, sp, trap vector) and jump to usertrap
    ld t1, 0(a0)       # kernel_satp
    ld sp, 8(a0)       # kernel_sp
    ld t0, 16(a0)      # kernel_trap (usertrap)
    csrw satp, t1
    sfence.vma
    jr t0
```

### 4.3 Strict $W \oplus X$ User Address Space Construction

When creating a user process, `proc_pagetable` constructs a clean Sv39 tree mapping:
1. `0x3ffffff000`: Trampoline (Kernel Code, `PTE_V | PTE_R | PTE_X | PTE_G`).
2. `0x3fffffe000`: Trapframe (Kernel Data, `PTE_V | PTE_R | PTE_W`).
3. `0x00000000`: User Page 0 (Code & Rodata, `PTE_V | PTE_R | PTE_X | PTE_U`, **non-writable**).
4. `0x00001000`: User Page 1 (Stack & Data, `PTE_V | PTE_R | PTE_W | PTE_U`, **non-executable**).

Any attempt by user code to modify its own text triggers a Store Page Fault (`scause = 15`); any attempt to execute instructions from the stack triggers an Instruction Page Fault (`scause = 12`).

---

# Part 5: Console Syscalls & The Minimal Interactive Shell

With the privilege boundary operational, we constructed the final layer: a POSIX-like system call subsystem and an interactive shell executing purely in Ring 3.

### 5.1 The System Call Subsystem (`LeanXv6/Syscall.lean`)

Syscalls are identified by standard numbers passed in register `a7`:
- `SYS_exit` (2): Process termination.
- `SYS_read` (5): Buffered console input.
- `SYS_write` (16): Console output.

To translate user buffers safely, `uva2pa` maps user addresses to kernel physical addresses:

```lean
-- LeanXv6/Syscall.lean
fn uva2pa (p uva) [ra s0 s1] := do
  mv s0 p
  mv s1 uva
  li t0 0x1000
  let isStackLbl ← freshLabel "uva_stack"
  let doneLbl ← freshLabel "uva_done"
  bgeu s1 t0 isStackLbl
  -- Page 0 (Code/Rodata): user_code_pa + offset
  ld t1 PROC_OFFSET_USER_CODE_PA s0
  add a0 t1 s1
  j doneLbl
  label isStackLbl
  -- Page 1 (Stack/Data): user_stack_pa + (offset - 0x1000)
  ld t1 PROC_OFFSET_USER_STACK_PA s0
  sub s1 s1 t0
  add a0 t1 s1
  label doneLbl
```

`sys_read` implements terminal line discipline:
- Polling UART Line Status Register (`0x10000005`) bit 0.
- Handling backspace (`\b` = 8, `DEL` = 127) by erasing previous characters visually (`\b \b`) and rewinding the buffer pointer.
- Terminating on Enter (`\r` = 13 or `\n` = 10) with automatic null-termination.

### 5.2 The User Shell (`LeanXv6/Shell.lean`)

The user shell is assembled as a position-independent 4KB binary (`shell_image`) embedded in kernel `.rodata`. At boot, the kernel copies it into a fresh physical page, sets up the page table, and context-switches to Ring 3.

```lean
-- LeanXv6/Shell.lean
def shell_image : AsmM Unit := do
  section_ .rodata
  align 12
  globl "shell_image_start"
  label "shell_image_start"
  emitRaw ".option push\n.option norelax"

  -- User Mode Entry Point (VA 0x00000000)
  globl "_shell_entry"
  label "_shell_entry"
  li sp 0x1ff0 -- Top of Page 1 user stack

  -- Display Welcome Banner via SYS_write
  lla a0 "shell_banner"
  jal ra "print_str"

  -- Main Interactive Command Loop
  label "shell_loop"
  lla a0 "shell_prompt" -- "xv6$ "
  jal ra "print_str"

  -- Read command line into buffer at VA 0x1000
  li a7 SYS_read; li a0 0; li a1 0x1000; li a2 128
  ecall

  beqz a0 "shell_loop" -- Empty line (Enter)

  -- Command: help
  li a0 0x1000; lla a1 "cmd_help"; jal ra "strcmp"
  beqz a0 "do_help"

  -- Command: info
  li a0 0x1000; lla a1 "cmd_info"; jal ra "strcmp"
  beqz a0 "do_info"

  -- Command: clear
  li a0 0x1000; lla a1 "cmd_clear"; jal ra "strcmp"
  beqz a0 "do_clear"

  -- Command: exit
  li a0 0x1000; lla a1 "cmd_exit"; jal ra "strcmp"
  beqz a0 "do_exit"

  -- Command: echo <args>
  -- Parses 'echo ' prefix, prints arguments, and outputs newline...
```

The shell binary contains its own user-space implementations of `strlen`, `strcmp`, and `print_str`, executing strictly in Ring 3.

### 5.3 Live Terminal Execution

Running `make test` pipes interactive commands into QEMU:

```text
=== xv6-lean: Booted into Supervisor mode! ===
=== xv6-lean: MMU Sv39 paging enabled successfully via MCL static tables! ===
=== xv6-lean: Supervisor trap vector (stvec := kernelvec) installed! ===
=== xv6-lean: Initializing physical page allocator (kinit)... ===
=== xv6-lean: Physical page allocator (kinit/kalloc/kfree) verified successfully! ===
=== xv6-lean: Initializing process table and kernel stacks (procinit)... ===
=== xv6-lean: Running Process Subsystem verification test suite... ===
=== xv6-lean: Verified all 64 process slots initialized with valid 4KB kstacks! ===
=== xv6-lean: Context-switching into Process 1 via swtch... ===
=== xv6-lean: forkret reached! Process 1 running on newly allocated kstack! ===
=== xv6-lean: Launching User Mode Interactive Shell (Ring 3)... ===

============================================================
            Welcome to xv6-lean Interactive Shell!          
  Architecture: RISC-V 64-bit (Ring 3 User Mode, Sv39 MMU)  
  Type 'help' for available commands.                       
============================================================

xv6$ help
xv6-lean Shell Builtin Commands:
  help        - Display this help message
  info        - Display system architecture and memory status
  echo <text> - Print arguments to standard output
  clear       - Clear the terminal screen
  exit        - Terminate shell and cleanly return to kernel
xv6$ info
System Architecture Information:
  OS: xv6-lean (Formally Typed MIT xv6 in Lean 4)
  Target: RISC-V RV64GC (QEMU virt)
  Execution Mode: Ring 3 User Mode (U-mode)
  Paging: Sv39 3-level page tables with W^X enforcement
  Syscalls: SYS_exit (2), SYS_read (5), SYS_write (16)
xv6$ echo Shell automated test passed
Shell automated test passed
xv6$ exit
Exiting shell. Goodbye!
=== xv6-lean: User Mode process terminated via SYS_exit! ===
=== xv6-lean: Interactive Shell exited. Reclaiming process resources... ===
=== xv6-lean: Shell process cleanly reclaimed. Kernel execution finished! ===
```

When the user types `exit`, the shell invokes `SYS_exit(0)`. The kernel intercepts the environment call, transitions the process to `ZOMBIE`, restores the supervisor trap vector, context-switches back to kernel `main`, and invokes `freeproc` to reclaim the user physical pages and process slot.

---

# Verification Metrics & Architectural Summary

| Layer | Implementation Component | Formal Guarantees |
|---|---|---|
| **Paging** | Machine Configuration Language (MCL) | Strict $W \oplus X$, Kernel Isolation, 4KB Alignment |
| **Memory** | Physical Page Allocator (`kalloc`/`kfree`) | 0x88000000 boundary guard, zero-scrubbing |
| **Concurrency** | Process Table (`procTable`, `swtch`) | 16-byte stack alignment, callee-saved preservation |
| **Privilege** | Trampoline Page (`uservec`/`userret`) | Atomic register exchange via `sscratch`, user isolation |
| **I/O & Shell** | Syscalls & Interactive User Shell (`sh`) | Ring 3 user mode execution, memory-safe translation |

### Specifications Compliance (`libspec`)

```text
Specification (HEAD (Live Spec)) Components (94 total across 11 modules):
  • spec.app: 8 components (Boot, Build, ELF Separation)
  • spec.mcl: 15 components (Paging, Encoding, W⊕X Proofs)
  • spec.trust: 5 components (PMP, Delegation, UART)
  • spec.unicompiler: 11 components (AsmM Monad, Stage W)
  • spec.layers: 5 components (Syscall Interface, Trapframe)
  • spec.trap: 10 components (Vectors, Diagnostics, Diagnostics)
  • spec.stage_w: 8 components (Calling Convention, Stack Alignment)
  • spec.kalloc: 8 components (Freelist, Scrubbing, Bounds)
  • spec.proc: 11 components (procTable, Context Switch, ForkRet)
  • spec.user: 6 components (Trampoline, Privilege Drop, Trap Return)
  • spec.shell: 7 components (Syscalls, Drivers, Interactive Shell)
```

### Roadmap to v1.0.0
With the User Mode interactive shell operational, our next milestones include:
1. **VirtIO Disk Driver & Buffer Cache (`bcache`)**.
2. **Crash-Resilient Logging & Inode Filesystem**.
3. **Dynamic Process Forking (`SYS_fork`, `SYS_wait`) & ELF Executable Loading (`SYS_exec`)**.

*The complete codebase, specifications, and proofs are available in the repository root.*
