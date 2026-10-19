'''
Specifications for the lean-xv6 Supervisor Trap Infrastructure and Diagnostics
(Corresponds to Domain I in design/10-boot-dag-and-parallel-initialization.md)
'''

from .err import Feat, Req

class TrapVectorReq(Req):
    '''The operating system shall provide a supervisor-mode trap handling
    infrastructure (kernelvec and kerneltrap) installed into CSR stvec to catch
    and handle all hardware interrupts and CPU exceptions.
    '''

class KernelVecAlignmentFeat(Feat):
    '''The kernelvec trap entry point shall be 16-byte aligned (at least 4-byte
    aligned) to satisfy RISC-V Direct Mode stvec requirements where bits [1:0] are zero.
    '''

class KernelTrapframeSaveRestoreFeat(Feat):
    '''The kernel trap entry sequence (kernelvec) shall allocate 256 bytes on the
    active stack, spill all 31 general-purpose registers (excluding zero), invoke the
    trap dispatcher, and cleanly restore all registers prior to returning via sret.
    '''

class StvecInstallationFeat(Feat):
    '''The boot sequence shall install the virtual address of kernelvec into
    the stvec CSR immediately upon activating Sv39 virtual memory.
    '''

class UartHexPrinterFeat(Feat):
    '''The target DSL and kernel runtime shall provide an efficient hex printer
    routine (uartPrintHex) capable of streaming 64-bit register values in hexadecimal
    notation directly to UART0 MMIO for low-level panic and fault debugging.
    '''

class TrapDiagnosticDumpFeat(Feat):
    '''Upon encountering an unhandled exception or CPU fault, the kernel trap
    dispatcher shall extract the faulting cause (scause), instruction pointer (sepc),
    and bad address/value (stval), printing formatted diagnostics over UART0 before halting.
    '''

class InterruptVsExceptionFeat(Feat):
    '''The supervisor trap dispatcher (kerneltrap) shall distinguish between
    asynchronous interrupts and synchronous exceptions by evaluating bit 63 of scause
    (signed negative comparison bltz), routing device interrupts to interrupt acknowledgment
    and routing exceptions to fault diagnostics.
    '''

class SupervisorPrivilegeCheckFeat(Feat):
    '''The kernel trap dispatcher shall verify via sstatus.SPP (bit 8) that traps
    entering kernelvec originated strictly from Supervisor mode, raising a fatal panic
    if entered from User mode.
    '''

class ParameterizedRegisterSpillFeat(Feat):
    '''The trapframe save and restore routines shall be parameterized via a compile-time
    declarative list of (Reg, Int) offset pairs (kernelTrapRegs), eliminating manual assembly
    repetition and guaranteeing reciprocal save/restore consistency across all 31 registers.
    '''
