# Trust boundary: the ISA

Everything above the ISA is proved. Everything at and below is the trusted base.

## Must be in the model (RV64, single hart first)
- Unprivileged: RV64IMA + Zicsr as a step function on regs, pc, memory.
- Privileged: M/S/U modes, CSRs xv6 uses (satp, stvec, sepc, scause, stval,
  sstatus, sie/sip, mstatus, mepc, medeleg/mideleg, pmp*), trap entry,
  sret/mret, ecall.
- Sv39 page-table walk and permission/ A/D bit behaviour.
- TLB: translations may be stale until sfence.vma. Model as nondeterministic
  choice between cached and current translation. Omitting this makes proofs
  unsound in a way tests will not reveal.
- Asynchronous interrupts: may arrive between any two instructions when enabled.
- Underspecified behaviour (WARL fields, misaligned access) is nondeterminism.
- Memory model: single hart = sequentially consistent. RVWMO only for multicore.

## Devices are not ISA
UART, PLIC, CLINT, virtio-disk need separate trusted models. Keep each thin
(e.g. disk = read block / write block; crash semantics added later).

## Sources for the model
1. Official Sail RISC-V model, if a Lean backend is usable for proofs (check).
2. Hand-written model of only the subset xv6 uses, differential-tested against
   Spike / QEMU on random instruction streams.

## Boot assumption
xv6-riscv boots with -bios none into M-mode at 0x80000000; no firmware is
trusted. Our own backend emits instruction words, so no assembler or linker is
trusted either (see 03).

## ISA at both ends of the top theorem
User programs are arbitrary RV64 code in U-mode. Top spec: processes are U-mode
harts over private address spaces plus a Unix-subset syscall relation, ecall
being the syscall entry. Same ISA model used at the bottom and in the spec.

## Out of scope
Microarchitecture, side channels, hardware faults.
