# Primitives and syscalls

## Primitives
Machine primitives are leaves, not a language. Declare each once with a view at
each level and a contract linking neighbours.

    structure Prim where
      name   : String
      sig    : List WTy x Option WTy      -- Low IR view
      code   : AsmBlock                   -- RISC-V instruction words
      effect : MachState -> Args sig -> MachState x Ret sig  -- contract

Expected set for xv6: csrr/csrw per used CSR, sfence.vma, wfi, fence,
ecall/sret/mret entry-exit stubs, swtch (callee-saved context switch), plus
MMIO load/store for UART, PLIC, CLINT, virtio. The code and contract of each
primitive is the whole hardware-facing proof obligation; everything else is
refinement.

## Syscalls
One description per syscall, from which everything else is derived.

    invocation sys_pipe where
      args   : fdarray : UserAddr
      errors : EFAULT | EMFILE | ENOMEM

Derived artifacts
- kernel decode signature (argument fetch from trapframe a0-a5, copyin checks)
- user-side stubs (xv6 usys.pl equivalent) so kernel and user ABI cannot drift
- syscall numbers (syscall.h) and the spec-level relation

Top-level kernel entry: handleEvent : Event -> KernelM Unit, where Event covers
ecall, device interrupt, timer interrupt, page fault, illegal instruction.
User syscall ABI: number in a7, args a0-a5, result in a0.
