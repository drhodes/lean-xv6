'''
Specifications for the lean-xv6 System Call Infrastructure & Interactive Shell Subsystem
(Corresponds to Milestone 3: Console I/O Syscalls and Minimal Interactive Shell)
'''

from .err import Feat, Req

class ShellSubsystemReq(Req):
    '''The operating system shall provide a minimal interactive shell running in
    User Mode (Ring 3) backed by console input/output system calls.
    '''

class UartRxPollingFeat(Feat):
    '''The UART driver shall provide receiver polling functionality (uartGetc)
    by inspecting Line Status Register (LSR) bit 0 (Data Ready) at MMIO address
    0x10000005 and reading incoming bytes from the receiver buffer register (RBR)
    at MMIO address 0x10000000.
    '''

class SyscallDispatchFeat(Feat):
    '''The kernel trap subsystem shall provide a system call dispatch mechanism
    routing syscall numbers passed in register a7 (e.g., SYS_read, SYS_write, SYS_exit)
    to corresponding system call handlers, extracting arguments from the trapframe,
    and returning results via trapframe->a0.
    '''

class SysWriteFeat(Feat):
    '''The system call subsystem shall implement SYS_write (syscall 16),
    transferring bytes from a user virtual memory buffer to the console UART0 device
    and returning the number of bytes written.
    '''

class SysReadFeat(Feat):
    '''The system call subsystem shall implement SYS_read (syscall 5), reading
    incoming character input from console UART0 into a user-space buffer with
    echoing and line-termination handling.
    '''

class SysExitFeat(Feat):
    '''The system call subsystem shall implement SYS_exit (syscall 2), terminating
    the user-space process and cleanly returning execution control to the kernel.
    '''

class UserShellExecutionFeat(Feat):
    '''The system shall provide an interactive shell program executing in User Mode
    (Ring 3) that displays a prompt, accepts and buffers user commands, executes
    built-in commands (help, echo, info, exit), and interacts with the terminal
    via standard system calls.
    '''
