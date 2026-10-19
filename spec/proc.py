'''
Specifications for the lean-xv6 Process Subsystem (procinit, struct proc, swtch)
(Corresponds to Domain II in design/10-boot-dag-and-parallel-initialization.md)
'''

from .err import Feat, Req

class ProcessSubsystemReq(Req):
    '''The operating system shall provide a multi-tasking process subsystem
    managing up to 64 concurrent processes (NPROC = 64) with dedicated kernel
    execution stacks and thread execution contexts.
    '''

class ProcStateFeat(Feat):
    '''The process subsystem shall represent process lifecycle states via an
    enumerated type supporting UNUSED (0), USED (1), SLEEPING (2), RUNNABLE (3),
    RUNNING (4), and ZOMBIE (5).
    '''

class ProcTableAllocationFeat(Feat):
    '''The kernel shall allocate a static 64-entry process table (proc) in writable
    data memory, where each entry is structured with explicit byte offsets for
    state, PID, kernel stack pointer, and execution context.
    '''

class ProcInitStackAllocationFeat(Feat):
    '''The initialization routine (procinit) shall iterate through all 64 process
    entries, initializing each process state to UNUSED and allocating a dedicated
    4KB physical frame from kalloc for each process's kernel execution stack (kstack).
    '''

class ThreadContextLayoutFeat(Feat):
    '''The thread context structure shall be exactly 112 bytes in size, holding
    the 14 RISC-V 64-bit callee-saved registers (ra, sp, s0 through s11) at 8-byte
    aligned offsets.
    '''

class ContextSwitchFeat(Feat):
    '''The context switch routine (swtch) shall take pointers to an outgoing context
    in register a0 and an incoming context in register a1, spill the caller's 14
    callee-saved registers into 0(a0)..104(a0), restore the target's 14 registers
    from 0(a1)..104(a1), and resume execution via ret.
    '''

class CoroutineContextSwitchTestFeat(Feat):
    '''The process subsystem shall include an in-kernel verification test that
    initializes an auxiliary execution context with a dedicated stack, switches
    execution into a test coroutine via swtch, and switches back to resume the caller.
    '''
