'''
Specifications for the lean-xv6 Abstraction Layers and System Call Interface
(Corresponds to design/04-abstraction-layers.md and design/05-primitives-and-syscalls.md)
'''

from .err import Feat, Req

class AbstractionLayersReq(Req):
    '''The operating system design shall be decomposed into 15 strict hierarchical
    layers (Layers 0 through 14) where each layer depends only on the layer immediately
    beneath it, culminating in the top-level specification Layer T.
    '''

class SyscallInterfaceFeat(Feat):
    '''The system call layer (Layer 14) shall be specified via a typed typeclass
    interface `class SysCall (m : Type -> Type)` capturing the 21 standard xv6
    system calls plus course extensions (trace and sysinfo).
    '''

class TrapframeAbiFeat(Feat):
    '''The operating system shall decode system call requests from the hardware
    trapframe, binding register a7 to the syscall number and registers a0 through
    a5 to typed syscall arguments, with return value placed in a0.
    '''

class UserStubEmissionFeat(Feat):
    '''The build pipeline shall automatically derive and emit user-space system
    call stubs (user/usys.S) directly from the `SysCall` typeclass specification.
    '''

class TopSpecRefinementFeat(Feat):
    '''The system shall formalize a top-level refinement theorem stating that
    execution of the compiled kernel image over the RISC-V ISA machine model
    refines the abstract Unix-like multi-process specification (Layer T).
    '''
