import «LeanXv6».RiscV

namespace LeanXv6.MCL

open LeanXv6.RiscV

/-!
# Machine Configuration Language (MCL)
Declarative specifications of hardware topology, memory regions,
and compile-time verified Sv39 page table construction.
-/

-- ============================================================================
-- 1. Memory Permissions & Mapping Descriptors
-- ============================================================================

inductive Perm where
  | none
  | r
  | rw
  | rx
  | rwx
  deriving Repr, DecidableEq, Inhabited

def Perm.isReadable : Perm → Bool
  | .r | .rw | .rx | .rwx => true
  | _ => false

def Perm.isWritable : Perm → Bool
  | .rw | .rwx => true
  | _ => false

def Perm.isExecutable : Perm → Bool
  | .rx | .rwx => true
  | _ => false

structure Mapping where
  name   : String
  va     : UInt64
  pa     : UInt64
  size   : UInt64
  perms  : Perm
  user   : Bool := false
  global : Bool := true
  deriving Repr, DecidableEq, Inhabited

structure MachineConfig where
  name       : String
  ramBase    : UInt64 := 0x80000000
  ramSize    : UInt64 := 128 * 1024 * 1024
  mappings   : List Mapping
  trapVector : String := "kernelvec"
  deriving Repr, Inhabited

-- ============================================================================
-- 2. Sv39 Page Table Entry (PTE) Encoding
-- ============================================================================

/-- Sv39 Page Table Entry constructor:
    Bits [53:10] = PPN
    Bit 7 = Dirty (D)
    Bit 6 = Accessed (A)
    Bit 5 = Global (G)
    Bit 4 = User (U)
    Bit 3 = Executable (X)
    Bit 2 = Writable (W)
    Bit 1 = Readable (R)
    Bit 0 = Valid (V)
-/
def makePte (ppn : UInt64) (perms : Perm) (user : Bool) (global : Bool) (isLeaf : Bool) : UInt64 :=
  let vBit : UInt64 := 1
  let rBit : UInt64 := if isLeaf && perms.isReadable then ((1 : UInt64) <<< 1) else 0
  let wBit : UInt64 := if isLeaf && perms.isWritable then ((1 : UInt64) <<< 2) else 0
  let xBit : UInt64 := if isLeaf && perms.isExecutable then ((1 : UInt64) <<< 3) else 0
  let uBit : UInt64 := if user then ((1 : UInt64) <<< 4) else 0
  let gBit : UInt64 := if global then ((1 : UInt64) <<< 5) else 0
  let aBit : UInt64 := ((1 : UInt64) <<< 6) -- pre-marked accessed
  let dBit : UInt64 := if perms.isWritable then ((1 : UInt64) <<< 7) else 0
  (ppn <<< 10) ||| vBit ||| rBit ||| wBit ||| xBit ||| uBit ||| gBit ||| aBit ||| dBit

/-- Constructs a leaf PTE directly from a Mapping descriptor -/
def Mapping.leafPte (m : Mapping) (paOffset : UInt64 := 0) : UInt64 :=
  makePte ((m.pa + paOffset) >>> 12) m.perms m.user m.global true

-- ============================================================================
-- 3. Invariant Checkers & Decidable Proofs
-- ============================================================================

/-- Strict W-xor-X: no mapping may be both writable and executable -/
def satisfiesWX (cfg : MachineConfig) : Bool :=
  cfg.mappings.all fun m => !(m.perms.isWritable && m.perms.isExecutable)

/-- Kernel isolation: no kernel or MMIO mapping grants user access -/
def kernelIsolated (cfg : MachineConfig) : Bool :=
  cfg.mappings.all fun m => m.user == false

/-- Page alignment: all virtual addresses, physical addresses, and sizes must be 4KB aligned -/
def allPageAligned (cfg : MachineConfig) : Bool :=
  cfg.mappings.all fun m =>
    (m.va % 4096 == 0) && (m.pa % 4096 == 0) && (m.size % 4096 == 0)

-- ============================================================================
-- 4. Concrete QEMU virt Machine Configuration
-- ============================================================================

def qemuVirtConfig : MachineConfig := {
  name := "qemu-riscv64-virt"
  ramBase := 0x80000000
  ramSize := 128 * 1024 * 1024
  mappings := [
    -- 1. UART0 (Console MMIO): 0x10000000 -> 0x10000000 (4KB, RW)
    { name := "uart0",    va := 0x10000000, pa := 0x10000000, size := 0x1000,   perms := .rw },

    -- 2. VirtIO Disk: 0x10001000 -> 0x10001000 (4KB, RW)
    { name := "virtio0",  va := 0x10001000, pa := 0x10001000, size := 0x1000,   perms := .rw },

    -- 3. PLIC (Interrupt Controller): 0x0c000000 -> 0x0c000000 (4MB, RW)
    { name := "plic",     va := 0x0c000000, pa := 0x0c000000, size := 0x400000, perms := .rw },

    -- 4. QEMU Test Finisher / Poweroff: 0x100000 -> 0x100000 (4KB, RW)
    { name := "test",     va := 0x100000,   pa := 0x100000,   size := 0x1000,   perms := .rw },

    -- 5. Kernel Text: 0x80000000 -> 0x80000000 (2MB, RX, No Write)
    { name := "text",     va := 0x80000000, pa := 0x80000000, size := 0x200000, perms := .rx },

    -- 6. Kernel Data & Free RAM: 0x80200000 -> 0x80200000 (126MB, RW, No Exec)
    { name := "ram_pool", va := 0x80200000, pa := 0x80200000, size := 0x7e00000, perms := .rw },

    -- 7. Trampoline: 0x3ffffff000 -> _trampoline (4KB, RX, No Write)
    { name := "trampoline", va := 0x3ffffff000, pa := 0x80001000, size := 0x1000, perms := .rx }
  ]
}

-- Automated compile-time verification of security invariants
theorem qemuVirt_satisfies_WX : satisfiesWX qemuVirtConfig = true := by
  decide

theorem qemuVirt_is_isolated : kernelIsolated qemuVirtConfig = true := by
  decide

theorem qemuVirt_aligned : allPageAligned qemuVirtConfig = true := by
  decide

-- ============================================================================
-- 5. Page Table Representation & Tree Compiler
-- ============================================================================

structure PageTable where
  name    : String
  level   : Nat
  entries : List (Nat × UInt64) := []
  deriving Repr, Inhabited

def PageTable.get (pt : PageTable) (idx : Nat) : UInt64 :=
  match pt.entries.find? (fun (i, _) => i == idx) with
  | some (_, val) => val
  | none => 0

def PageTable.set (pt : PageTable) (idx : Nat) (val : UInt64) : PageTable :=
  { pt with entries := (idx, val) :: pt.entries.filter (fun (i, _) => i != idx) }

def PageTable.emitAsm (pt : PageTable) : AsmM Unit := do
  data
  align 12
  globl pt.name
  label pt.name
  comment s!"Sv39 Level {pt.level} Page Table: {pt.name}"
  for i in [0:512] do
    let val := pt.get i
    quad val

/-- Builds the static Sv39 page tables for a MachineConfig at compile time -/
def buildPageTables (cfg : MachineConfig) : List PageTable :=
  let findPte (name : String) (offset : UInt64 := 0) : UInt64 :=
    match cfg.mappings.find? (·.name == name) with
    | some m => m.leafPte offset
    | none   => 0

  -- 1. Level 0 table for MMIO (UART0 at idx 0, VIRTIO0 at idx 1)
  let pt_l0_mmio :=
    { name := "boot_l0_mmio", level := 0, entries := [(0, findPte "uart0"), (1, findPte "virtio0")] }

  -- 2. Level 0 table for Low Devices (QEMU test finisher at idx 256)
  let pt_l0_low :=
    { name := "boot_l0_low", level := 0, entries := [(256, findPte "test")] }

  -- 3. Level 0 table for Trampoline (idx 511)
  let pt_l0_tramp :=
    { name := "boot_l0_tramp", level := 0, entries := [(511, findPte "trampoline")] }

  -- 4. Level 1 table for MMIO (PLIC at idx 96, 97)
  let pt_l1_0 :=
    { name := "boot_l1_0", level := 1, entries := [(96, findPte "plic" 0), (97, findPte "plic" 0x200000)] }

  -- 5. Level 1 table for RAM (Text 2MB at idx 0; Free RAM 126MB at idx 1..63)
  let pt_l1_2 :=
    let ramList : List (Nat × UInt64) :=
      (List.range 63).map (fun i =>
        let idx := i + 1
        let pte := findPte "ram_pool" ((idx.toUInt64 - 1) * 0x200000)
        (idx, pte))
    { name := "boot_l1_2", level := 1, entries := (0, findPte "text") :: ramList }

  -- 6. Level 1 table for Trampoline
  let pt_l1_511 :=
    { name := "boot_l1_511", level := 1, entries := [] }

  -- 7. Level 2 Root Page Table
  let pt_l2 :=
    { name := "boot_l2", level := 2, entries := [] }

  [pt_l2, pt_l1_0, pt_l1_2, pt_l0_low, pt_l0_mmio, pt_l1_511, pt_l0_tramp]

def virtPageTables : List PageTable := buildPageTables qemuVirtConfig

/-- Emits all static Sv39 page tables into assembly data blocks (.align 12) -/
def emitVirtPageTables : AsmM Unit := do
  for pt in virtPageTables do
    pt.emitAsm

def storeTableEntry (tableSym : String) (idx : Nat) (valReg : Reg) : AsmM Unit := do
  la t1 tableSym
  let offset := idx * 8
  if offset < 2048 then
    sd valReg (offset : Int) t1
  else
    li t2 (offset : Int)
    add t1 t1 t2
    sd valReg 0 t1

/-- Emits instructions to connect a parent table entry to a child page table -/
def linkPageTable (parent : String) (idx : Nat) (child : String) : AsmM Unit := do
  la t0 child
  srli t0 t0 12
  slli t0 t0 10
  ori t0 t0 1 -- PTE_V
  storeTableEntry parent idx t0

/-- Tree connections between parent tables and child tables in the Sv39 hierarchy -/
def virtPageTableLinks : List (String × Nat × String) := [
  ("boot_l2",     0,   "boot_l1_0"),
  ("boot_l2",     2,   "boot_l1_2"),
  ("boot_l2",     511, "boot_l1_511"),
  ("boot_l1_0",   0,   "boot_l0_low"),
  ("boot_l1_0",   128, "boot_l0_mmio"),
  ("boot_l1_511", 511, "boot_l0_tramp")
]

/-- Programs satp with Sv39 mode (8 << 60) and root table PPN, then flushes TLB -/
def setSatp (rootSym : String := "boot_l2") : AsmM Unit := do
  la t0 rootSym
  srli t0 t0 12
  li t1 (8 <<< 60 : Int)
  or_ t0 t0 t1
  csrw .satp t0
  sfence_vma

/-- Monadic instruction macro to link page tables and activate Sv39 MMU paging -/
def enablePaging (rootSym : String := "boot_l2") : AsmM Unit := do
  comment "=== Activate Sv39 MMU Paging (MCL) ==="
  for (parent, idx, child) in virtPageTableLinks do
    linkPageTable parent idx child
  setSatp rootSym

-- ============================================================================
-- 6. Compile-Time Proofs on Generated Page Tables
-- ============================================================================

def findPageTable (name : String) : PageTable :=
  match virtPageTables.find? (·.name == name) with
  | some pt => pt
  | none    => { name := "", level := 0, entries := [] }

theorem virtPageTables_count : virtPageTables.length = 7 := by
  rfl

-- Kernel text is executable and not writable
theorem virtPageTables_text_rx :
  let pte_text := (findPageTable "boot_l1_2").get 0
  ((pte_text &&& ((1 : UInt64) <<< 3)) != 0) && ((pte_text &&& ((1 : UInt64) <<< 2)) == 0) = true := by
  rfl

-- Free RAM is writable and not executable
theorem virtPageTables_ram_rw :
  let pte_ram1 := (findPageTable "boot_l1_2").get 1
  ((pte_ram1 &&& ((1 : UInt64) <<< 2)) != 0) && ((pte_ram1 &&& ((1 : UInt64) <<< 3)) == 0) = true := by
  decide

-- PLIC is writable and not executable
theorem virtPageTables_plic_rw :
  let pte_plic := (findPageTable "boot_l1_0").get 96
  ((pte_plic &&& ((1 : UInt64) <<< 2)) != 0) && ((pte_plic &&& ((1 : UInt64) <<< 3)) == 0) = true := by
  rfl

end LeanXv6.MCL
