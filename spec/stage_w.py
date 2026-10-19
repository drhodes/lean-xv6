'''
Specifications for the Unicompiler Low IR Stage W and Calling Convention
(Corresponds to Stage W in design/01-principles.md and design/03-language-stack.md)
'''

from .err import Feat, Req

class StageWReq(Req):
    '''The Unicompiler shall provide a typed Low IR layer (Stage W) bridging
    high-level kernel logic and raw RISC-V assembly, featuring automatic calling
    convention management, typed function signatures, and structured frame lowering.
    '''

class AbiArgumentBindingFeat(Feat):
    '''Stage W functions shall bind declared formal parameters positionally to
    the RISC-V standard C-ABI argument registers (a0 through a7), supporting up
    to 8 register-passed arguments with compile-time arity validation.
    '''

class CalleeSavedRegisterSpillFeat(Feat):
    '''Stage W function prologue lowering shall automatically allocate stack frame
    space and spill all designated callee-saved registers (s0 through s11) and the
    return address register (ra) onto the stack prior to executing the function body.
    '''

class CalleeSavedRegisterRestoreFeat(Feat):
    '''Stage W function epilogue lowering shall automatically reload all spilled
    callee-saved registers (s0 through s11) and the return address register (ra),
    restore the original stack pointer, and emit the `ret` instruction.
    '''

class FunctionReturnConventionFeat(Feat):
    '''Stage W functions shall establish register a0 as the canonical return value
    register for 64-bit scalars and pointers, providing combinators to return values
    and automatically route exit control flow through the epilogue.
    '''

class StackFrameAlignmentFeat(Feat):
    '''Every stack frame allocated by Stage W shall round its total byte size up
    to a multiple of 16 bytes to guarantee strict compliance with the RISC-V ABI
    stack pointer alignment invariant (sp % 16 == 0).
    '''

class StageWFunctionSyntaxFeat(Feat):
    '''The system shall provide a declarative Lean 4 syntax macro
    `fn name (args...) [saves regs...] := do body` elaborating directly into an
    AsmFunction with automated prologue, parameter binding, body execution, and epilogue.
    '''

class StageWCallConvenienceFeat(Feat):
    '''Stage W shall provide a typed invocation combinator `callFn target [args...]`
    that marshals actual argument registers or values into ABI registers a0..aN
    prior to emitting the `call target` instruction.
    '''
