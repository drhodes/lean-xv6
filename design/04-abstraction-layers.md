# Abstraction layers for xv6 (draft, to be refined against the real source)

Each layer sees only the one below. Interfaces deliberately tiny.
To do: map actual xv6-riscv functions onto these rows and mark leaks.

| # | Layer | Interface |
|---|-------|-----------|
| 0 | ISA + devices (trusted) | step, device ops |
| 1 | RISC-V prims | csr read/write, sfence.vma, trap entry/exit, swtch |
| 2 | physical memory | kalloc, kfree |
| 3 | page tables | walk, map, unmap |
| 4 | address space | uvmalloc, uvmfree, uvmcopy, copyin, copyout |
| 5 | kernel threads / scheduler (1 CPU) | allocproc, yield, sched, swtch |
| 6 | sleep/wakeup | sleep(chan), wakeup(chan) |
| 7 | process lifecycle | fork, exit, wait, kill, sbrk, getpid |
| 8 | pipes | pipealloc, piperead, pipewrite |
| 9 | disk + buffer cache | bread, bwrite, brelse |
| 10 | inodes | ialloc, iget, ilock, readi, writei, itrunc |
| 11 | directories + paths | dirlookup, dirlink, namei |
| 12 | file descriptors | open, close, read, write, dup, fstat |
| 13 | log (crash safety) | begin_op, end_op, log_write |
| 14 | syscall dispatch | handleEvent : Event -> KernelM Unit |
| T | top spec | processes as U-mode harts + Unix-subset syscall relation |

Cross-cutting operations to watch
- exit/wait: touches proc, address space, files, parent reparenting.
- exec: address space rebuild, argument copy, file read.
- pipes: blocking via sleep/wakeup with a lock-protected buffer.
- trap handling: user vs kernel trap, timer-driven yield.
- Log layer interacts with every FS write; interface must stay begin/end/write.

Rule of thumb for hiding: nothing above the page-table layer knows PTE bit
layout; nothing above the inode layer knows on-disk dinode format; nothing
above the buffer cache knows block devices exist.
