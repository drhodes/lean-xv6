'''
Specifications for the lean-xv6 Trust Boundary and Hardware Device Interfaces
(Corresponds to design/02-trust-boundary.md)
'''

from .err import Feat, Req

class TrustBoundaryReq(Req):
    '''The operating system verification boundary shall be drawn strictly at the
    RISC-V ISA and hardware device models. No external compilers (e.g. LLVM) or
    unverified C runtime libraries shall be included in the trusted computing base.
    '''

class PmpIsolationFeat(Feat):
    '''The boot sequence shall configure Machine-mode Physical Memory Protection
    (pmpaddr0, pmpcfg0) to grant Supervisor mode full access to physical RAM
    and MMIO device memory while isolating Machine-only state.
    '''

class InterruptDelegationFeat(Feat):
    '''The boot sequence shall program medeleg and mideleg to delegate all
    standard interrupts and exceptions from Machine mode to Supervisor mode.
    '''

class Uart16550DeviceFeat(Feat):
    '''The operating system shall provide a driver for the 16550-compatible UART
    MMIO console device located at physical and virtual address 0x10000000.
    '''

class QemuTestFinisherFeat(Feat):
    '''The operating system shall support the QEMU virt test finisher MMIO device
    located at address 0x100000 with protocol code 0x5555 to support clean,
    headless automated test exit with return code 0.
    '''
