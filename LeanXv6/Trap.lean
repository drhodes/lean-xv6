import «LeanXv6».RiscV

namespace LeanXv6.Trap

open LeanXv6.RiscV

/-!
# Supervisor Trap Handling & Diagnostics in Lean 4
(Domain I in the Boot DAG: `kernelvec`, `kerneltrap`, diagnostic fault reporting)
-/

/-- Standard list of 31 registers spilled in kernelvec trapframe -/
def kernelTrapRegs : List (Reg × Int) := [
  (ra, 0),   (sp, 8),   (gp, 16),  (tp, 24),
  (t0, 32),  (t1, 40),  (t2, 48),  (s0, 56),  (s1, 64),
  (a0, 72),  (a1, 80),  (a2, 88),  (a3, 96),  (a4, 104),
  (a5, 112), (a6, 120), (a7, 128),
  (s2, 136), (s3, 144), (s4, 152), (s5, 160), (s6, 168),
  (s7, 176), (s8, 184), (s9, 192), (s10, 200), (s11, 208),
  (t3, 216), (t4, 224), (t5, 232), (t6, 240)
]

/-- Spill all registers onto the 256-byte stack frame -/
def spillKernelRegs (base : Reg := sp) : AsmM Unit := do
  for (r, off) in kernelTrapRegs do
    sd r off base

/-- Restore all registers from the 256-byte stack frame -/
def restoreKernelRegs (base : Reg := sp) : AsmM Unit := do
  for (r, off) in kernelTrapRegs do
    ld r off base

/-- Formatted diagnostic dump of CPU fault state to UART0 -/
def printTrapDiagnostics : AsmM Unit := do
  uartPrint "\n========================================\n"
  uartPrint "!!! KERNEL PANIC: Unexpected CPU Trap !!!\n"
  uartPrint "========================================\n"
  
  uartPrint "scause : "
  csrr a0 .scause
  uartPrintHex a0
  uartPrint "\n"

  uartPrint "sepc   : "
  csrr a0 .sepc
  uartPrintHex a0
  uartPrint "\n"

  uartPrint "stval  : "
  csrr a0 .stval
  uartPrintHex a0
  uartPrint "\n"

  uartPrint "sstatus: "
  csrr a0 .sstatus
  uartPrintHex a0
  uartPrint "\n========================================\n"
  uartPrint "Kernel execution halted.\n"

/-- Supervisor trap dispatcher function -/
function kerneltrap := do
  -- Read trap cause
  csrr a0 .scause

  -- Bit 63 = 1 indicates an asynchronous interrupt; 0 indicates an exception
  -- Check if scause is an interrupt (a0 < 0 in signed 64-bit comparison)
  let interruptLbl ← freshLabel "is_interrupt"
  let endLbl ← freshLabel "trap_done"

  bltz a0 interruptLbl

  -- Exception path: unexpected kernel exception -> diagnostic panic
  printTrapDiagnostics
  exitQemu 1
  infiniteWait "panic_halt"

  label interruptLbl
  -- For now, acknowledge interrupt and return cleanly
  uartPrint "=== Supervisor interrupt received ===\n"

  label endLbl
  ret

/-- Low-level assembly trap entry point installed into stvec -/
entryPoint kernelvec := do
  -- 1. Allocate 256 bytes for trapframe on active stack
  addi sp sp (-256)

  -- 2. Save all general-purpose registers
  spillKernelRegs sp

  -- 3. Call high-level trap dispatcher
  call kerneltrap

  -- 4. Restore all general-purpose registers
  restoreKernelRegs sp

  -- 5. Deallocate trapframe
  addi sp sp 256

  -- 6. Return from supervisor trap
  sret

/-- Installs kernelvec into stvec (Direct Mode, bits[1:0] = 00) -/
def installKernelTrap : AsmM Unit := do
  la t0 kernelvec
  csrw .stvec t0

end LeanXv6.Trap
