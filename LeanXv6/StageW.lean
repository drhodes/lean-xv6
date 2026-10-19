import «LeanXv6».RiscV

namespace LeanXv6.StageW

open LeanXv6.RiscV
open Lean

/-!
# Stage W: Low IR Functions & Calling Convention
(Corresponds to Stage W specifications in spec/stage_w.py)

Provides:
- ABI Argument Mapping (a0..a7)
- 16-byte aligned stack frame computation
- Callee-saved register spilling & restoration (prologue & epilogue)
- Declarative `fn` macro syntax with argument binding
- Invocation helper `callFn`
-/

/-- The 8 standard RISC-V ABI argument registers -/
def abiArgRegs : List Reg := [a0, a1, a2, a3, a4, a5, a6, a7]

/-- Computes 16-byte aligned stack frame size in bytes given slot count -/
def calcFrameSize (slots : Nat) : Int :=
  let rawBytes := slots * 8
  let aligned := ((rawBytes + 15) / 16) * 16
  (aligned : Int)

/-- Emits standard RISC-V function prologue: decrements sp and spills callee-saved registers -/
def emitPrologue (frameBytes : Int) (saves : List Reg) : AsmM Unit := do
  if frameBytes > 0 then
    addi sp sp (-frameBytes)
    for i in [:saves.length] do
      let r := saves[i]!
      sd r (i * 8) sp

/-- Emits standard RISC-V function epilogue: restores callee-saved registers, restores sp, and emits ret -/
def emitEpilogue (frameBytes : Int) (saves : List Reg) : AsmM Unit := do
  if frameBytes > 0 then
    for i in [:saves.length] do
      let r := saves[i]!
      ld r (i * 8) sp
    addi sp sp frameBytes
  ret

/-- Sets a return value from a register into a0 -/
def returnVal (r : Reg) : AsmM Unit := do
  if r != a0 then
    mv a0 r

/-- Sets an immediate return value into a0 -/
def returnImm (imm : Int) : AsmM Unit := do
  li a0 imm

/-- Marshals arguments into a0..aN and calls the target symbol -/
def callFn [ToSymbol α] (target : α) (args : List Reg := []) : AsmM Unit := do
  for i in [:args.length] do
    let actual := args[i]!
    let abi := abiArgRegs[i]!
    if actual != abi then
      mv abi actual
  call target

/-- Typeclass resolving multi-arity function bodies up to 8 arguments -/
class InvokeWithArgs (n : Nat) (α : Type) where
  invoke : α → AsmM Unit

instance : InvokeWithArgs 0 (AsmM Unit) where
  invoke f := f

instance : InvokeWithArgs 1 (Reg → AsmM Unit) where
  invoke f := f a0

instance : InvokeWithArgs 2 (Reg → Reg → AsmM Unit) where
  invoke f := f a0 a1

instance : InvokeWithArgs 3 (Reg → Reg → Reg → AsmM Unit) where
  invoke f := f a0 a1 a2

instance : InvokeWithArgs 4 (Reg → Reg → Reg → Reg → AsmM Unit) where
  invoke f := f a0 a1 a2 a3

instance : InvokeWithArgs 5 (Reg → Reg → Reg → Reg → Reg → AsmM Unit) where
  invoke f := f a0 a1 a2 a3 a4

instance : InvokeWithArgs 6 (Reg → Reg → Reg → Reg → Reg → Reg → AsmM Unit) where
  invoke f := f a0 a1 a2 a3 a4 a5

instance : InvokeWithArgs 7 (Reg → Reg → Reg → Reg → Reg → Reg → Reg → AsmM Unit) where
  invoke f := f a0 a1 a2 a3 a4 a5 a6

instance : InvokeWithArgs 8 (Reg → Reg → Reg → Reg → Reg → Reg → Reg → Reg → AsmM Unit) where
  invoke f := f a0 a1 a2 a3 a4 a5 a6 a7

/-- Stage W function block builder with automated prologue, invocation, and epilogue -/
def fnBlock [InvokeWithArgs n α] (name : String) (frameBytes : Int) (saves : List Reg) (body : α) : AsmM Unit := do
  functionBlock name do
    emitPrologue frameBytes saves
    InvokeWithArgs.invoke (n := n) body
    emitEpilogue frameBytes saves

end LeanXv6.StageW

-- ============================================================================
-- Declarative Syntax: `fn` Macro
-- ============================================================================

open Lean
open LeanXv6.RiscV
open LeanXv6.StageW

syntax (name := fnDecl) (docComment)? "fn " ident " (" ident* ")" (" [" ident* "]")? " := " doSeq : command

macro_rules
  | `(command| $[$doc:docComment]? fn $name:ident ( ) $[ [ $saves:ident* ] ]? := $body) => do
    let sym := Syntax.mkStrLit (toString name.getId)
    let savesList := match saves with
      | some s => s.toList
      | none   => []
    let numSaves := savesList.length
    let frameBytes := calcFrameSize numSaves
    let frameLit := Syntax.mkNumLit (toString frameBytes)

    let mut saveTerms : Array (TSyntax `term) := #[]
    for s in savesList do
      saveTerms := saveTerms.push (mkIdent s.getId)

    let fnBlockId := mkIdent `LeanXv6.StageW.fnBlock
    let asmFuncId := mkIdent `LeanXv6.RiscV.AsmFunction
    `($[$doc:docComment]? def $name : $asmFuncId := {
        name := $sym,
        code := $fnBlockId (n := 0) $sym $frameLit [ $saveTerms,* ] (do $body)
      })

  | `(command| $[$doc:docComment]? fn $name:ident ( $args:ident* ) $[ [ $saves:ident* ] ]? := $body) => do
    let sym := Syntax.mkStrLit (toString name.getId)
    let arityLit := Syntax.mkNumLit (toString args.size)
    let savesList := match saves with
      | some s => s.toList
      | none   => []
    let numSaves := savesList.length
    let frameBytes := calcFrameSize numSaves
    let frameLit := Syntax.mkNumLit (toString frameBytes)

    let mut saveTerms : Array (TSyntax `term) := #[]
    for s in savesList do
      saveTerms := saveTerms.push (mkIdent s.getId)

    let regType := mkIdent `LeanXv6.RiscV.Reg
    let mut typedArgs : Array (TSyntax `term) := #[]
    for a in args do
      let ta ← `(($a : $regType))
      typedArgs := typedArgs.push ta

    let fnBlockId := mkIdent `LeanXv6.StageW.fnBlock
    let asmFuncId := mkIdent `LeanXv6.RiscV.AsmFunction
    `($[$doc:docComment]? def $name : $asmFuncId := {
        name := $sym,
        code := $fnBlockId (n := $arityLit) $sym $frameLit [ $saveTerms,* ] (fun $typedArgs* => do $body)
      })
