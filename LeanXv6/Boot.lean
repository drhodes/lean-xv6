import «LeanXv6».RiscV
import «LeanXv6».MachineConfig
import «LeanXv6».Trap
import «LeanXv6».StageW
import «LeanXv6».Kalloc

namespace LeanXv6.Boot

open LeanXv6.RiscV
open LeanXv6.MCL
open LeanXv6.Trap
open LeanXv6.StageW
open LeanXv6.Kalloc

/-!
# xv6 Boot Code in Lean 4
Expressed via our monadic RISC-V DSL (`entryPoint`, `function`, `globalData`, `fn`).
-/

/-- Stage W verified function with argument binding and callee-saved registers -/
fn kernelAdd (x y) [ra s0] := do
  add s0 x y
  uartPrint "=== xv6-lean: Stage W Low IR function (kernelAdd) executed successfully! ===\n"
  returnVal s0

-- Main function running in Supervisor mode
function main := do
  uartPrint "\n=== xv6-lean: Booted into Supervisor mode! ===\n"

  -- Activate Sv39 MMU Paging using declarative Machine Configuration (MCL)
  enablePaging "boot_l2"
  uartPrint "=== xv6-lean: MMU Sv39 paging enabled successfully via MCL static tables! ===\n"

  -- Install supervisor trap vector (stvec := kernelvec)
  installKernelTrap
  uartPrint "=== xv6-lean: Supervisor trap vector (stvec := kernelvec) installed! ===\n"

  -- Verify Stage W Low IR calling convention
  li a0 40
  li a1 2
  callFn kernelAdd [a0, a1]

  -- Initialize physical memory page allocator (Domain II)
  uartPrint "=== xv6-lean: Initializing physical page allocator (kinit)... ===\n"
  callFn kinit []

  -- Run in-kernel page allocator test suite
  callFn testKalloc []

  -- Exit cleanly in QEMU test environment
  exitQemu 0
  infiniteWait

-- Start function running in Machine mode, setting up S-mode handover
function start := do
  -- 1. Set mstatus.MPP to Supervisor mode (bits [12:11] = 0b01)
  csrModify .mstatus (3 <<< 11) (1 <<< 11)

  -- 2. Set mepc = main (referring to `main` directly!)
  la   t0 main
  csrw .mepc t0

  -- 3. Disable paging for now: satp = 0
  csrw .satp zero

  -- 4. Delegate all interrupts and exceptions to Supervisor mode
  li   t0 0xffff
  csrw .medeleg t0
  csrw .mideleg t0

  -- 5. Give S-mode access to all physical memory via PMP
  li   t0 0x3fffffffffffffff
  csrw .pmpaddr0 t0
  li   t0 0xf
  csrw .pmpcfg0 t0

  -- 6. Store CPU core ID in tp
  csrr tp .mhartid

  -- 7. Drop privilege to Supervisor mode and jump to main()!
  mret

-- Boot entry point: hardware starts here at 0x80000000 in M-mode
entryPoint _entry := do
  la   sp "stack0"
  li   a0 4096
  csrr a1 .mhartid
  addi a1 a1 1
  mul  a0 a0 a1
  add  sp sp a0

  -- Compile-time verified call to `start`!
  call start
  infiniteSpin

-- Per-CPU stack allocation in .data (aligned to 16 bytes)
globalData stack0 := do
  space (4096 * 8) -- 8 CPU cores * 4096 bytes

/-- Combined boot block containing entry, start, main, trap vector, stack0, and compiled page tables -/
def bootBlock : AsmM Unit := do
  _entry.code
  start.code
  main.code
  kernelAdd.code
  kfree.code
  kalloc.code
  kinit.code
  testKalloc.code
  kmem_freelist.code
  kernelvec.code
  kerneltrap.code
  stack0.code
  emitVirtPageTables

/-- Emitted GNU-compatible RV64 assembly text -/
def bootAssembly : String :=
  emitAssembly bootBlock

end LeanXv6.Boot
