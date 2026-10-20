'''
Specifications for the lean-xv6 Multi-Process Scheduling & Lifecycle Subsystem
(Corresponds to Milestone 5: fork, wait, getpid, scheduler, yield)
'''

from .err import Feat, Req

class ProcessLifecycleReq(Req):
    '''The operating system shall provide complete dynamic process lifecycle operations
    including process duplication (fork), child exit synchronization (wait), process
    identification (getpid), and preemptive or cooperative round-robin CPU scheduling.
    '''

class SysForkFeat(Feat):
    '''The system call subsystem shall implement SYS_fork (syscall 1), duplicating
    the calling process's user memory address space (Page 0 Code/Rodata and Page 1
    Stack/Data), copying trapframe state with child a0 initialized to 0, setting
    parent-child relationship pointers, marking the child RUNNABLE, and returning
    the child PID to the parent caller.
    '''

class SysWaitFeat(Feat):
    '''The system call subsystem shall implement SYS_wait (syscall 3), scanning the
    process table for child processes of the calling process, releasing ZOMBIE child
    resources via freeproc, writing the child's exit status code to user virtual memory,
    and returning the exited child's PID to the parent caller.
    '''

class SysGetpidFeat(Feat):
    '''The system call subsystem shall implement SYS_getpid (syscall 11), extracting
    the current process's process identifier (PID) from struct proc and returning
    it to user space in register a0.
    '''

class RoundRobinSchedulerFeat(Feat):
    '''The kernel shall implement a round-robin CPU scheduler loop (scheduler) that
    continuously inspects the process table for RUNNABLE processes, sets the selected
    process state to RUNNING, and dispatches execution via context switch (swtch).
    '''

class ProcessYieldFeat(Feat):
    '''The process subsystem shall provide a cooperative yield operation (yield)
    that transitions the current running process back to RUNNABLE and transfers
    CPU execution back to the scheduler loop via swtch.
    '''

class MultiProcessForkWaitTestFeat(Feat):
    '''The operating system shall verify multi-process execution by executing a user
    process that invokes SYS_fork to spawn a child process, verifies differential
    return codes (PID in parent, 0 in child), exits the child process via SYS_exit,
    and collects the child exit status in the parent via SYS_wait.
    '''
