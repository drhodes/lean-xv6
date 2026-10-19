import Lean

namespace LeanXv6.RiscV

/-!
# RISC-V Target DSL in Lean 4 (Stage R)
A monadic DSL for emitting RV64 machine instructions and assembler directives
aligned with MIT 6.S081 (xv6-riscv) boot code (`entry.S`, `start.c`, `kernel.ld`).
-/

-- ============================================================================
-- 1. Registers and CSRs
-- ============================================================================

inductive Reg where
  | zero | ra | sp | gp | tp
  | t0 | t1 | t2
  | s0 | s1
  | a0 | a1 | a2 | a3 | a4 | a5 | a6 | a7
  | s2 | s3 | s4 | s5 | s6 | s7 | s8 | s9 | s10 | s11
  | t3 | t4 | t5 | t6
  deriving Repr, DecidableEq, Inhabited

def Reg.toString : Reg → String
  | .zero => "zero" | .ra   => "ra"   | .sp   => "sp"   | .gp   => "gp"
  | .tp   => "tp"   | .t0   => "t0"   | .t1   => "t1"   | .t2   => "t2"
  | .s0   => "s0"   | .s1   => "s1"   | .a0   => "a0"   | .a1   => "a1"
  | .a2   => "a2"   | .a3   => "a3"   | .a4   => "a4"   | .a5   => "a5"
  | .a6   => "a6"   | .a7   => "a7"   | .s2   => "s2"   | .s3   => "s3"
  | .s4   => "s4"   | .s5   => "s5"   | .s6   => "s6"   | .s7   => "s7"
  | .s8   => "s8"   | .s9   => "s9"   | .s10  => "s10"  | .s11  => "s11"
  | .t3   => "t3"   | .t4   => "t4"   | .t5   => "t5"   | .t6   => "t6"

instance : ToString Reg := ⟨Reg.toString⟩

-- Standard register variables in scope
def zero := Reg.zero
def ra   := Reg.ra
def sp   := Reg.sp
def gp   := Reg.gp
def tp   := Reg.tp
def t0   := Reg.t0
def t1   := Reg.t1
def t2   := Reg.t2
def s0   := Reg.s0
def s1   := Reg.s1
def a0   := Reg.a0
def a1   := Reg.a1
def a2   := Reg.a2
def a3   := Reg.a3
def a4   := Reg.a4
def a5   := Reg.a5
def a6   := Reg.a6
def a7   := Reg.a7
def s2   := Reg.s2
def s3   := Reg.s3
def s4   := Reg.s4
def s5   := Reg.s5
def s6   := Reg.s6
def s7   := Reg.s7
def s8   := Reg.s8
def s9   := Reg.s9
def s10  := Reg.s10
def s11  := Reg.s11
def t3   := Reg.t3
def t4   := Reg.t4
def t5   := Reg.t5
def t6   := Reg.t6

inductive CSR where
  -- Machine mode CSRs
  | mhartid | mstatus | mepc | medeleg | mideleg | mie | mip
  | mtvec | mscratch | mcause | mtval | menvcfg | mcounteren
  | pmpcfg0 | pmpaddr0
  -- Supervisor mode CSRs
  | sstatus | sepc | scause | stval | stvec | sscratch | sie | sip
  | satp | stimecmp
  deriving Repr, DecidableEq, Inhabited

def CSR.toString : CSR → String
  | .mhartid    => "mhartid"
  | .mstatus    => "mstatus"
  | .mepc       => "mepc"
  | .medeleg    => "medeleg"
  | .mideleg    => "mideleg"
  | .mie        => "mie"
  | .mip        => "mip"
  | .mtvec      => "mtvec"
  | .mscratch   => "mscratch"
  | .mcause     => "mcause"
  | .mtval      => "mtval"
  | .menvcfg    => "menvcfg"
  | .mcounteren => "mcounteren"
  | .pmpcfg0    => "pmpcfg0"
  | .pmpaddr0   => "pmpaddr0"
  | .sstatus    => "sstatus"
  | .sepc       => "sepc"
  | .scause     => "scause"
  | .stval      => "stval"
  | .stvec      => "stvec"
  | .sscratch   => "sscratch"
  | .sie        => "sie"
  | .sip        => "sip"
  | .satp       => "satp"
  | .stimecmp   => "stimecmp"

instance : ToString CSR := ⟨CSR.toString⟩

-- ============================================================================
-- 2. Section ADT & Properties
-- ============================================================================

inductive Section where
  | text                      -- .text (executable code)
  | rodata                    -- .rodata (read-only data)
  | data                      -- .data (initialized mutable data)
  | bss                       -- .bss (zero-initialized data)
  | trampoline                -- "trampsec" in xv6 kernel.ld (trampoline page)
  | custom (name : String)    -- user-defined section
  deriving Repr, DecidableEq, Inhabited

def Section.toDirective : Section → String
  | .text       => ".section .text"
  | .rodata     => ".section .rodata"
  | .data       => ".section .data"
  | .bss        => ".section .bss"
  | .trampoline => ".section trampsec, \"ax\""
  | .custom s   => s!".section {s}"

def Section.isExecutable : Section → Bool
  | .text | .trampoline => true
  | _                   => false

def Section.isWritable : Section → Bool
  | .data | .bss => true
  | _            => false

-- ============================================================================
-- 3. Instructions & Assembly Items
-- ============================================================================

inductive Instr where
  -- Arithmetic & Logic
  | add   (rd rs1 rs2 : Reg)
  | addi  (rd rs1 : Reg) (imm : Int)
  | sub   (rd rs1 rs2 : Reg)
  | mul   (rd rs1 rs2 : Reg)
  | and_  (rd rs1 rs2 : Reg)
  | or_   (rd rs1 rs2 : Reg)
  | xor_  (rd rs1 rs2 : Reg)
  | andi  (rd rs : Reg) (imm : Int)
  | ori   (rd rs : Reg) (imm : Int)
  | xori  (rd rs : Reg) (imm : Int)
  | slli  (rd rs : Reg) (shamt : Nat)
  | srli  (rd rs : Reg) (shamt : Nat)
  | srai  (rd rs : Reg) (shamt : Nat)
  | sll   (rd rs1 rs2 : Reg)
  | srl   (rd rs1 rs2 : Reg)
  | sra   (rd rs1 rs2 : Reg)
  -- Loads & Stores
  | ld    (rd : Reg) (offset : Int) (base : Reg)
  | sd    (rs : Reg) (offset : Int) (base : Reg)
  | lw    (rd : Reg) (offset : Int) (base : Reg)
  | sw    (rs : Reg) (offset : Int) (base : Reg)
  | lb    (rd : Reg) (offset : Int) (base : Reg)
  | sb    (rs : Reg) (offset : Int) (base : Reg)
  -- Pseudo-instructions
  | li    (rd : Reg) (imm : Int)
  | la    (rd : Reg) (sym : String)
  | lla   (rd : Reg) (sym : String)
  | mv    (rd rs : Reg)
  -- Control Flow
  | j     (label : String)
  | jal   (rd : Reg) (label : String)
  | jalr  (rd : Reg) (rs : Reg) (offset : Int)
  | call  (sym : String)
  | ret
  | beq   (rs1 rs2 : Reg) (label : String)
  | bne   (rs1 rs2 : Reg) (label : String)
  | beqz  (rs : Reg) (label : String)
  | bnez  (rs : Reg) (label : String)
  | blt   (rs1 rs2 : Reg) (label : String)
  | bge   (rs1 rs2 : Reg) (label : String)
  | bltu  (rs1 rs2 : Reg) (label : String)
  | bgeu  (rs1 rs2 : Reg) (label : String)
  | bgez  (rs : Reg) (label : String)
  | blez  (rs : Reg) (label : String)
  | bgtz  (rs : Reg) (label : String)
  | bltz  (rs : Reg) (label : String)
  -- Privileged & CSRs
  | csrr  (rd : Reg) (csr : CSR)
  | csrw  (csr : CSR) (rs : Reg)
  | csrrw (rd : Reg) (csr : CSR) (rs : Reg)
  | csrs  (csr : CSR) (rs : Reg)
  | csrc  (csr : CSR) (rs : Reg)
  | sfence_vma
  | wfi
  | ecall
  | sret
  | mret
  deriving Repr, DecidableEq, Inhabited

def Instr.toString : Instr → String
  | .add rd rs1 rs2      => s!"    add {rd}, {rs1}, {rs2}"
  | .addi rd rs1 imm     => s!"    addi {rd}, {rs1}, {imm}"
  | .sub rd rs1 rs2      => s!"    sub {rd}, {rs1}, {rs2}"
  | .mul rd rs1 rs2      => s!"    mul {rd}, {rs1}, {rs2}"
  | .and_ rd rs1 rs2     => s!"    and {rd}, {rs1}, {rs2}"
  | .or_ rd rs1 rs2      => s!"    or {rd}, {rs1}, {rs2}"
  | .xor_ rd rs1 rs2     => s!"    xor {rd}, {rs1}, {rs2}"
  | .andi rd rs imm      => s!"    andi {rd}, {rs}, {imm}"
  | .ori rd rs imm       => s!"    ori {rd}, {rs}, {imm}"
  | .xori rd rs imm      => s!"    xori {rd}, {rs}, {imm}"
  | .slli rd rs shamt    => s!"    slli {rd}, {rs}, {shamt}"
  | .srli rd rs shamt    => s!"    srli {rd}, {rs}, {shamt}"
  | .srai rd rs shamt    => s!"    srai {rd}, {rs}, {shamt}"
  | .sll rd rs1 rs2      => s!"    sll {rd}, {rs1}, {rs2}"
  | .srl rd rs1 rs2      => s!"    srl {rd}, {rs1}, {rs2}"
  | .sra rd rs1 rs2      => s!"    sra {rd}, {rs1}, {rs2}"
  | .ld rd offset base   => s!"    ld {rd}, {offset}({base})"
  | .sd rs offset base   => s!"    sd {rs}, {offset}({base})"
  | .lw rd offset base   => s!"    lw {rd}, {offset}({base})"
  | .sw rs offset base   => s!"    sw {rs}, {offset}({base})"
  | .lb rd offset base   => s!"    lb {rd}, {offset}({base})"
  | .sb rs offset base   => s!"    sb {rs}, {offset}({base})"
  | .li rd imm           => s!"    li {rd}, {imm}"
  | .la rd sym           => s!"    la {rd}, {sym}"
  | .lla rd sym          => s!"    lla {rd}, {sym}"
  | .mv rd rs            => s!"    mv {rd}, {rs}"
  | .j label             => s!"    j {label}"
  | .jal rd label        => s!"    jal {rd}, {label}"
  | .jalr rd rs offset   => s!"    jalr {rd}, {offset}({rs})"
  | .call sym            => s!"    call {sym}"
  | .ret                 => "    ret"
  | .beq rs1 rs2 label   => s!"    beq {rs1}, {rs2}, {label}"
  | .bne rs1 rs2 label   => s!"    bne {rs1}, {rs2}, {label}"
  | .beqz rs label       => s!"    beqz {rs}, {label}"
  | .bnez rs label       => s!"    bnez {rs}, {label}"
  | .blt rs1 rs2 label   => s!"    blt {rs1}, {rs2}, {label}"
  | .bge rs1 rs2 label   => s!"    bge {rs1}, {rs2}, {label}"
  | .bltu rs1 rs2 label  => s!"    bltu {rs1}, {rs2}, {label}"
  | .bgeu rs1 rs2 label  => s!"    bgeu {rs1}, {rs2}, {label}"
  | .bgez rs label       => s!"    bgez {rs}, {label}"
  | .blez rs label       => s!"    blez {rs}, {label}"
  | .bgtz rs label       => s!"    bgtz {rs}, {label}"
  | .bltz rs label       => s!"    bltz {rs}, {label}"
  | .csrr rd csr         => s!"    csrr {rd}, {csr}"
  | .csrw csr rs         => s!"    csrw {csr}, {rs}"
  | .csrrw rd csr rs     => s!"    csrrw {rd}, {csr}, {rs}"
  | .csrs csr rs         => s!"    csrs {csr}, {rs}"
  | .csrc csr rs         => s!"    csrc {csr}, {rs}"
  | .sfence_vma          => "    sfence.vma"
  | .wfi                 => "    wfi"
  | .ecall               => "    ecall"
  | .sret                => "    sret"
  | .mret                => "    mret"

instance : ToString Instr := ⟨Instr.toString⟩

inductive AsmItem where
  | section (s : Section)
  | globl   (sym : String)
  | align   (n : Nat)
  | space   (bytes : Nat)
  | quad    (val : UInt64)
  | quadSym (sym : String) (addend : Int := 0)
  | asciz   (str : String)
  | raw     (code : String)
  | label   (name : String)
  | instr   (i : Instr)
  | comment (txt : String)
  deriving Repr, DecidableEq, Inhabited

def AsmItem.toString : AsmItem → String
  | .section s       => s.toDirective
  | .globl sym       => s!".globl {sym}"
  | .align n         => s!".align {n}"
  | .space bytes     => s!"    .space {bytes}"
  | .quad val        => s!"    .quad {val}"
  | .quadSym sym add => if add == 0 then s!"    .quad {sym}" else s!"    .quad {sym} + {add}"
  | .asciz str       => s!"    .asciz \"{str}\""
  | .raw code        => code
  | .label name      => s!"{name}:"
  | .instr i         => Instr.toString i
  | .comment txt     => s!"    # {txt}"

instance : ToString AsmItem := ⟨AsmItem.toString⟩

-- ============================================================================
-- 4. AsmM Monad and Builder
-- ============================================================================

structure AsmState where
  items        : Array AsmItem := #[]
  labelCounter : Nat := 0
  deriving Inhabited

abbrev AsmM := StateM AsmState

@[inline] def emit (item : AsmItem) : AsmM Unit :=
  modify fun s => { s with items := s.items.push item }

@[inline] def emitInstr (i : Instr) : AsmM Unit :=
  emit (.instr i)

-- Directives
def section_ (s : Section) : AsmM Unit := emit (.section s)
def globl    (sym : String)  : AsmM Unit := emit (.globl sym)
def align    (n : Nat)       : AsmM Unit := emit (.align n)
def space    (bytes : Nat)   : AsmM Unit := emit (.space bytes)
def label    (name : String) : AsmM Unit := emit (.label name)
def asciz    (str : String)  : AsmM Unit := emit (.asciz str)
def emitRaw  (code : String) : AsmM Unit := emit (.raw code)
def comment  (txt : String)  : AsmM Unit := emit (.comment txt)

-- Shorthand section selectors
def text       : AsmM Unit := section_ .text
def data       : AsmM Unit := section_ .data
def rodata     : AsmM Unit := section_ .rodata
def bss        : AsmM Unit := section_ .bss
def trampoline : AsmM Unit := section_ .trampoline

-- Monadic Instructions
def add   (rd rs1 rs2 : Reg)     : AsmM Unit := emitInstr (.add rd rs1 rs2)
def addi  (rd rs1 : Reg) (imm : Int) : AsmM Unit := emitInstr (.addi rd rs1 imm)
def sub   (rd rs1 rs2 : Reg)     : AsmM Unit := emitInstr (.sub rd rs1 rs2)
def mul   (rd rs1 rs2 : Reg)     : AsmM Unit := emitInstr (.mul rd rs1 rs2)
def and_  (rd rs1 rs2 : Reg)     : AsmM Unit := emitInstr (.and_ rd rs1 rs2)
def or_   (rd rs1 rs2 : Reg)     : AsmM Unit := emitInstr (.or_ rd rs1 rs2)
def xor_  (rd rs1 rs2 : Reg)     : AsmM Unit := emitInstr (.xor_ rd rs1 rs2)
def andi  (rd rs : Reg) (imm : Int)   : AsmM Unit := emitInstr (.andi rd rs imm)
def ori   (rd rs : Reg) (imm : Int)   : AsmM Unit := emitInstr (.ori rd rs imm)
def xori  (rd rs : Reg) (imm : Int)   : AsmM Unit := emitInstr (.xori rd rs imm)
def slli  (rd rs : Reg) (shamt : Nat) : AsmM Unit := emitInstr (.slli rd rs shamt)
def srli  (rd rs : Reg) (shamt : Nat) : AsmM Unit := emitInstr (.srli rd rs shamt)
def srai  (rd rs : Reg) (shamt : Nat) : AsmM Unit := emitInstr (.srai rd rs shamt)
def sll   (rd rs1 rs2 : Reg)     : AsmM Unit := emitInstr (.sll rd rs1 rs2)
def srl   (rd rs1 rs2 : Reg)     : AsmM Unit := emitInstr (.srl rd rs1 rs2)
def sra   (rd rs1 rs2 : Reg)     : AsmM Unit := emitInstr (.sra rd rs1 rs2)

def quad    (val : UInt64) : AsmM Unit := emit (.quad val)
def quadSym (sym : String) (addend : Int := 0) : AsmM Unit := emit (.quadSym sym addend)

def ld    (rd : Reg) (offset : Int) (base : Reg) : AsmM Unit := emitInstr (.ld rd offset base)
def sd    (rs : Reg) (offset : Int) (base : Reg) : AsmM Unit := emitInstr (.sd rs offset base)
def lw    (rd : Reg) (offset : Int) (base : Reg) : AsmM Unit := emitInstr (.lw rd offset base)
def sw    (rs : Reg) (offset : Int) (base : Reg) : AsmM Unit := emitInstr (.sw rs offset base)
def lb    (rd : Reg) (offset : Int) (base : Reg) : AsmM Unit := emitInstr (.lb rd offset base)
def sb    (rs : Reg) (offset : Int) (base : Reg) : AsmM Unit := emitInstr (.sb rs offset base)

def li    (rd : Reg) (imm : Int) : AsmM Unit := emitInstr (.li rd imm)
def mv    (rd rs : Reg)             : AsmM Unit := emitInstr (.mv rd rs)

def j     (lbl : String) : AsmM Unit := emitInstr (.j lbl)
def jal   (rd : Reg) (lbl : String) : AsmM Unit := emitInstr (.jal rd lbl)
def ret                  : AsmM Unit := emitInstr .ret
def jalr  (rd rs : Reg) (offset : Int := 0) : AsmM Unit := emitInstr (.jalr rd rs offset)
def jr    (rs : Reg)     : AsmM Unit := emitInstr (.jalr zero rs 0)
def beq   (rs1 rs2 : Reg) (lbl : String) : AsmM Unit := emitInstr (.beq rs1 rs2 lbl)
def bne   (rs1 rs2 : Reg) (lbl : String) : AsmM Unit := emitInstr (.bne rs1 rs2 lbl)
def beqz  (rs : Reg) (lbl : String)      : AsmM Unit := emitInstr (.beqz rs lbl)
def bnez  (rs : Reg) (lbl : String)      : AsmM Unit := emitInstr (.bnez rs lbl)
def blt   (rs1 rs2 : Reg) (lbl : String) : AsmM Unit := emitInstr (.blt rs1 rs2 lbl)
def bge   (rs1 rs2 : Reg) (lbl : String) : AsmM Unit := emitInstr (.bge rs1 rs2 lbl)
def bltu  (rs1 rs2 : Reg) (lbl : String) : AsmM Unit := emitInstr (.bltu rs1 rs2 lbl)
def bgeu  (rs1 rs2 : Reg) (lbl : String) : AsmM Unit := emitInstr (.bgeu rs1 rs2 lbl)
def bgez  (rs : Reg) (lbl : String)      : AsmM Unit := emitInstr (.bgez rs lbl)
def blez  (rs : Reg) (lbl : String)      : AsmM Unit := emitInstr (.blez rs lbl)
def bgtz  (rs : Reg) (lbl : String)      : AsmM Unit := emitInstr (.bgtz rs lbl)
def bltz  (rs : Reg) (lbl : String)      : AsmM Unit := emitInstr (.bltz rs lbl)

def csrr  (rd : Reg) (csr : CSR)            : AsmM Unit := emitInstr (.csrr rd csr)
def csrw  (csr : CSR) (rs : Reg)            : AsmM Unit := emitInstr (.csrw csr rs)
def csrrw (rd : Reg) (csr : CSR) (rs : Reg) : AsmM Unit := emitInstr (.csrrw rd csr rs)
def csrs  (csr : CSR) (rs : Reg)            : AsmM Unit := emitInstr (.csrs csr rs)
def csrc  (csr : CSR) (rs : Reg)            : AsmM Unit := emitInstr (.csrc csr rs)
def mret                                    : AsmM Unit := emitInstr .mret
def sret                                    : AsmM Unit := emitInstr .sret
def ecall                                   : AsmM Unit := emitInstr .ecall
def sfence_vma                              : AsmM Unit := emitInstr .sfence_vma
def wfi                                     : AsmM Unit := emitInstr .wfi

/-- Generates a unique assembler label with the given prefix -/
def freshLabel (pfx : String := "L") : AsmM String := do
  let s ← get
  let lbl := s!"{pfx}_{s.labelCounter}"
  set { s with labelCounter := s.labelCounter + 1 }
  return lbl

/-- Helper to print a string through QEMU virt UART0 (0x10000000) -/
def uartPrint (msg : String) : AsmM Unit := do
  li t0 0x10000000
  for c in msg.toList do
    li t1 (c.toNat : Int)
    sb t1 0 t0

/-- Emits a compact loop printing a 64-bit register value in hexadecimal ("0x...") to UART0 -/
def uartPrintHex (valReg : Reg) (tmpUart : Reg := t3) (tmpVal : Reg := t4) (tmpDigit : Reg := t5) (tmpShift : Reg := t6) (tmpTen : Reg := t2) : AsmM Unit := do
  let loopLbl ← freshLabel "hexdump_loop"
  let letterLbl ← freshLabel "hexdump_letter"
  let emitLbl ← freshLabel "hexdump_emit"

  li tmpUart 0x10000000
  -- Print "0x"
  li tmpDigit 48 -- '0'
  sb tmpDigit 0 tmpUart
  li tmpDigit 120 -- 'x'
  sb tmpDigit 0 tmpUart

  mv tmpVal valReg
  li tmpShift 60
  li tmpTen 10

  label loopLbl
  srl tmpDigit tmpVal tmpShift
  andi tmpDigit tmpDigit 0xf
  bge tmpDigit tmpTen letterLbl
  addi tmpDigit tmpDigit 48 -- '0'
  j emitLbl

  label letterLbl
  addi tmpDigit tmpDigit 87 -- 'a' - 10

  label emitLbl
  sb tmpDigit 0 tmpUart
  addi tmpShift tmpShift (-4)
  bgez tmpShift loopLbl

/-- Modifies a CSR by clearing a bitmask and setting new bits: csr = (csr & ~clearMask) | setBits -/
def csrModify (csr : CSR) (clearMask : Int) (setBits : Int) : AsmM Unit := do
  csrr t0 csr
  if clearMask != 0 then
    li t1 (~~~clearMask)
    and_ t0 t0 t1
  if setBits != 0 then
    li t1 setBits
    or_ t0 t0 t1
  csrw csr t0

/-- Signals the QEMU virt test finisher device (0x100000) to exit cleanly -/
def exitQemu (code : UInt32 := 0) : AsmM Unit := do
  li t0 0x100000
  li t1 (if code == 0 then 0x5555 else 0x3333)
  sw t1 0 t0

/-- Enters an infinite busy-wait spin loop -/
def infiniteSpin (lbl : String := "spin") : AsmM Unit := do
  label lbl
  j lbl

/-- Enters an infinite low-power wait loop using wfi -/
def infiniteWait (lbl : String := "halt") : AsmM Unit := do
  label lbl
  wfi
  j lbl

-- Typeclass for referencing symbols (either a raw String or an AsmFunction)
class ToSymbol (α : Type) where
  toSymbol : α → String

instance : ToSymbol String where
  toSymbol s := s

structure AsmFunction where
  name : String
  code : AsmM Unit

instance : ToSymbol AsmFunction where
  toSymbol f := f.name

def call [ToSymbol α] (target : α) : AsmM Unit :=
  emitInstr (.call (ToSymbol.toSymbol target))

def la [ToSymbol α] (rd : Reg) (target : α) : AsmM Unit :=
  emitInstr (.la rd (ToSymbol.toSymbol target))

def lla [ToSymbol α] (rd : Reg) (target : α) : AsmM Unit :=
  emitInstr (.lla rd (ToSymbol.toSymbol target))

-- Combinators
def functionBlock (name : String) (body : AsmM Unit) (alignment : Nat := 2) : AsmM Unit := do
  section_ .text
  align alignment
  globl name
  label name
  body

def entryPointBlock (name : String := "_entry") (body : AsmM Unit) (alignment : Nat := 4) : AsmM Unit := do
  section_ .text
  align alignment
  globl name
  label name
  body

def globalDataBlock (name : String) (sec : Section := .data) (alignment : Nat := 16) (body : AsmM Unit) : AsmM Unit := do
  section_ sec
  align alignment
  globl name
  label name
  body

def emitAssembly (m : AsmM Unit) : String :=
  let (_, s) := m.run {}
  String.intercalate "\n" (s.items.toList.map toString) ++ "\n"

end LeanXv6.RiscV

-- ============================================================================
-- 5. Macros: function, entryPoint, globalData
-- ============================================================================

open Lean

syntax (name := functionDecl) (docComment)? "function " ident " := " doSeq : command
syntax (name := entryPointDecl) (docComment)? "entryPoint " ident " := " doSeq : command
syntax (name := globalDataDecl) (docComment)? "globalData " ident (ident)? (num)? " := " doSeq : command

macro_rules
  | `(command| $[$doc:docComment]? function $name:ident := $body) =>
    let sym := Syntax.mkStrLit (toString name.getId)
    `($[$doc:docComment]? def $name : LeanXv6.RiscV.AsmFunction := {
        name := $sym,
        code := LeanXv6.RiscV.functionBlock $sym do $body
      })

  | `(command| $[$doc:docComment]? entryPoint $name:ident := $body) =>
    let sym := Syntax.mkStrLit (toString name.getId)
    `($[$doc:docComment]? def $name : LeanXv6.RiscV.AsmFunction := {
        name := $sym,
        code := LeanXv6.RiscV.entryPointBlock $sym do $body
      })

  | `(command| $[$doc:docComment]? globalData $name:ident := $body) =>
    let sym := Syntax.mkStrLit (toString name.getId)
    `($[$doc:docComment]? def $name : LeanXv6.RiscV.AsmFunction := {
        name := $sym,
        code := LeanXv6.RiscV.globalDataBlock $sym .data 16 do $body
      })
