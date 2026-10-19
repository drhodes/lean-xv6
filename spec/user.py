'''
Specifications for the lean-xv6 User-Mode Transition & Trampoline Subsystem (uservec, userret, usertrap)
(Corresponds to Milestone 2: Dropping into User Mode and Syscall Trapping)
'''

from .err import Feat, Req

class UserModeTransitionReq(Req):
    '''The operating system shall support dropping CPU privilege from Supervisor
    Mode (S-mode) to User Mode (U-mode) and fielding traps returning from U-mode
    via a dual-mapped trampoline page and per-process Sv39 user page tables.
    '''

class UserPageTableStructureFeat(Feat):
    '''The process subsystem shall construct an Sv39 multi-level user page table
    for each user process, mapping the trampoline code at virtual address
    TRAMPOLINE (0x3ffffff000), the process trapframe at TRAPFRAME (0x3fffffe000),
    and user program instructions at low virtual memory with user access permissions (PTE_U).
    '''

class UserRetTrampolineFeat(Feat):
    '''The return trampoline (userret) shall execute at virtual address TRAMPOLINE,
    switch the MMU page table pointer (satp) to the user process page table, restore
    the 31 saved user registers from TRAPFRAME, set sscratch to TRAPFRAME, and drop
    privilege to U-mode via sret.
    '''

class UserVecTrampolineFeat(Feat):
    '''The user trap entry trampoline (uservec) shall execute when an exception or
    interrupt occurs in U-mode, swap a0 with sscratch to acquire the TRAPFRAME pointer,
    spill the 31 user registers into TRAPFRAME, switch satp back to the kernel root
    page table, and jump to the kernel trap handler (usertrap).
    '''

class UserTrapDispatcherFeat(Feat):
    '''The user trap handler (usertrap) shall inspect scause to distinguish
    environment calls from U-mode (scause == 8), advance sepc beyond the trapped
    ecall instruction, and resume user execution via usertrapret.
    '''

class UserModeExecutionVerificationFeat(Feat):
    '''The kernel shall include an in-kernel verification test that allocates a
    user process, loads a test instruction sequence into user memory, drops CPU
    privilege into U-mode, handles an ecall trap returning to kernel mode, and
    completes the round-trip user execution sequence cleanly.
    '''
