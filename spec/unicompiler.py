'''
Specifications for the Unicompiler and Multi-Stage Compilation Pipeline
(Corresponds to design/01-principles.md, design/03-language-stack.md, and LeanXv6/RiscV.lean)
'''

from .err import Feat, Req

class UnicompilerReq(Req):
    '''The operating system shall be written in an integrated, multi-stage Lean 4
    compilation pipeline (the Unicompiler) that lowers high-level OS concepts
    down to emitted RISC-V assembly words with end-to-end formal proofs.
    '''

class StageRMonadicDslFeat(Feat):
    '''The target assembly DSL (Stage R) shall provide a monadic instruction stream
    with type-safe registers, CSRs, Section ADT (.text, .data, .rodata, .bss, trampsec),
    and custom command macros (entryPoint, function, globalData).
    '''

class CompileTimeSymbolResolutionFeat(Feat):
    '''The target DSL shall permit referencing Lean function definitions (AsmFunction)
    directly as call targets and symbol addresses to verify label existence at
    Lean compile time rather than relying on external linker symbol resolution.
    '''

class StageWLowIrFeat(Feat):
    '''The Unicompiler Low IR (Stage W) shall provide structured imperative constructs,
    typed function argument declarations, automated RISC-V ABI argument register
    allocation (a0..a7), and stack frame management with callee-saved registers.
    '''

class StageLLayoutFeat(Feat):
    '''The Unicompiler Layout stage (Stage L) shall provide verified bitfields
    and structured layout definitions for OS hardware and disk structures
    (Trapframe, Sv39 PTE, dinode, superblock) without depending on C struct alignment.
    '''

class StageKKernelDslFeat(Feat):
    '''The Unicompiler Kernel DSL (Stage K) shall express high-level OS algorithms
    over typed objects and maps with explicit monadic effects for thread suspension
    (sleep, yield) and interrupt enable/disable state.
    '''

class MachineStateSemanticsFeat(Feat):
    '''Every instruction in the target DSL shall possess operational step
    semantics over an explicit machine state (MachState), enabling automated
    proofs of memory framing, register framing, and block contracts.
    '''

class PerLevelDebuggerFeat(Feat):
    '''Each language level in the Unicompiler stack shall provide a dedicated
    debugger interface supporting single-stepping, state inspection, invariant
    verification, and differential lockstep execution against adjacent layers.
    '''

class MacroDocCommentPreservationFeat(Feat):
    '''The custom command macros (function, entryPoint, globalData) shall support
    optional doc comments (/-- ... -/), seamlessly attaching documentation to the
    generated AsmFunction definitions.
    '''

class PreLabelAlignmentFeat(Feat):
    '''Function and entry point declaration combinators shall emit .align directives
    immediately prior to label and .globl declarations so that entry symbols in the
    ELF symbol table strictly satisfy hardware alignment constraints (e.g. 16-byte alignment).
    '''

class FreshLabelGenerationFeat(Feat):
    '''The monadic target DSL (AsmM) shall maintain an internal label counter and
    provide a combinator `freshLabel (pfx : String)` to dynamically allocate unique,
    non-colliding assembler labels across unrolled macro loops and conditional blocks.
    '''
