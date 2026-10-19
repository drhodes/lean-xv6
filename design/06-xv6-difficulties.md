# Where xv6 is hard

1. Kernel concurrency: multicore with spinlocks, interrupts enabled in kernel.
   Plan: CPUS=1 first; model interrupts at defined points; revisit with RVWMO.
2. Blocking in kernel: sleep/wakeup and swtch mean per-process kernel stacks
   and suspended kernel code. Needs a thin "kernel threads" layer (row 5).
3. Crash safety: log layer is only meaningful with a crash semantics for the
   disk (FSCQ-style). Do last; initially prove the FS without crashes.
4. No spec exists: define a small Unix subset (fork/exec/exit/wait/pipe/fd
   semantics). We own the top interface, so we can keep it narrow.
5. TLB / sfence.vma discipline must be explicit in the proof (see 02).
6. Timer interrupts preempt arbitrary kernel/user code; yield points must be
   modelled so layer proofs do not assume atomicity they do not have.
7. Devices (virtio) are asynchronous; keep the trusted model minimal.

Mitigating: xv6 is ~6k lines, already layered per the xv6 book, usertests give
differential testing, Hyperkernel/FSCQ/Yggdrasil show the techniques work.
