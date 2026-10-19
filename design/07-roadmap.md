# Roadmap

## 0. The Unicompiler (The Multi-Stage Compilation & Debugging Engine)
An integrated, unified Lean 4 compilation pipeline that lowers high-level OS concepts down to emitted RISC-V assembly words with end-to-end proofs and per-level debugging:
- **Layered DSLs & Macros**: Stages K (Kernel DSL) $\to$ L (Layout/Bitfields) $\to$ W (Low IR) $\to$ R (RISC-V Assembly).
- **First-Class Functions with Arguments**: Declarative syntax (`function name (args...) := do ...`) with automatic ABI argument binding (`a0..a7`), callee-saved register management, and stack frames.
- **Embedded Static Linker**: In-Lean symbol resolution, section layout (`.text`, `.data`, `trampsec` at `0x80000000` / `0x3ffffff000`), and PC-relative offset computation without trusting external linkers.
- **Machine State Semantics & Frame Proofs**: Explicit operational transitions over `MachState`, proving frame lemmas (`add_mem_unchanged`, store isolation, register invariants) and Hoare triples over instruction blocks.
- **Per-Level Debuggers**: Each language level in the unicompiler has its own inspector, stepper, invariant checker, and differential lockstep simulator.

## 1. ISA Model & Target DSL (RV64IMA+Zicsr, M/S/U, Sv39)
- Target DSL in Lean 4 (Section ADT, monadic instructions, type-safe registers/CSRs). *(Milestone reached: boots in QEMU!)*
- Operational semantics on `MachState`, step transition, and core frame lemmas.
- Differential test harness vs Spike/QEMU.

## 2. Kernel Boot & Early Hardware Initialization
- `_entry` in M-mode, per-CPU stack initialization, `start` transition to S-mode via `mret`. *(Milestone reached: verified in QEMU)*
- PMP memory protection, delegation of interrupts (`medeleg`, `mideleg`), UART MMIO drivers.
- **Machine Configuration Language (MCL)**: Declarative memory topology, compile-time Sv39 page table compilation with $W \oplus X$ / isolation proofs, and Supervisor `satp` MMU activation. *(Milestone reached: verified in QEMU)*
- **Boot Dependency Graph (DAG) & Parallel Domains**:
  - Partition boot tasks into three orthogonal domains (Traps/Interrupts, Memory/Processes, and Storage/Tables) to eliminate artificial sequential boot bottlenecks.
  - Compile-time static pre-initialization of buffer/inode/file tables (`bcache`, `itable`, `ftable`).
  - Multi-hart boot pipeline with an explicit synchronization barrier before `userinit` (Process 0).

## 3. The System Call Layer (Layer 14)
- `class SysCall (m : Type → Type)` interface covering the 21 xv6-riscv syscalls + 6.S081 `trace` and `sysinfo`.
- Trapframe ABI decoding (`a7`, `a0..a5`), `usertrap`, and typed dispatch.
- User-space stub emission (`user/usys.S`) derived directly from the syscall interface.
- Syscall trace monitor & debugger (`<pid>: syscall <name>(<args>) -> <ret>`).

## 4. Layout Stage (Bitfields & Structs)
- Port key xv6 structures: `Trapframe`, Sv39 `PTE`, `struct proc`, `dinode`, `superblock`.

## 5. Layers 2–4: Memory Management
- `kalloc` / `kfree` physical memory allocator with refcounts.
- Page tables: `walk`, `map`, `unmap`, and `vmprint` page table debugger.
- User address spaces: `uvmalloc`, `uvmfree`, `copyin`, `copyout`.

## 6. Process Lifecycle & Scheduler (Single CPU)
- `allocproc`, kernel threads, `swtch`, `sleep`/`wakeup`, `fork`, `exit`, `wait`, `kill`.
- Run 6.S081 usertests subset.

## 7. File System & Pipes
- Pipes with sleep/wakeup.
- Inode layer, directory lookup, file descriptors, and crash-safe logging.

## 8. Top Theorem
- ISA machine running image refines the abstract OS specification (Layer T).

---

## Open Questions & Architecture Notes
- Unicompiler lowering strategy: macro expansion vs structured inductive ASTs for Stage W $\to$ Stage R.
- Coupling relations between adjacent layers for differential lockstep debugging.
- Handling asynchronous interrupts and TLB invalidation (`sfence.vma`) discipline in proofs.
