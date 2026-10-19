import «LeanXv6».RiscV
import «LeanXv6».StageW
import «LeanXv6».Kalloc
import «LeanXv6».Trap

namespace LeanXv6.Proc

open LeanXv6.RiscV
open LeanXv6.StageW
open LeanXv6.Kalloc
open LeanXv6.Trap

/-!
# Process Subsystem & Context Switching (Domain II)
Corresponds to Domain II in design/10-boot-dag-and-parallel-initialization.md
and spec/proc.py.

Manages the 64-entry process table (`procTable`), allocates per-process
kernel execution stacks via `kalloc`, and provides kernel thread context
switching via `swtch`.
-/

-- ============================================================================
-- 1. Constants & Process State Definitions
-- ============================================================================

/-- Maximum number of concurrent processes -/
def NPROC : Nat := 64

/-- Process lifecycle states -/
inductive ProcState where
  | unused   : ProcState -- 0
  | used     : ProcState -- 1
  | sleeping : ProcState -- 2
  | runnable : ProcState -- 3
  | running  : ProcState -- 4
  | zombie   : ProcState -- 5
  deriving Repr, DecidableEq

def PROC_STATE_UNUSED   : Int := 0
def PROC_STATE_USED     : Int := 1
def PROC_STATE_SLEEPING : Int := 2
def PROC_STATE_RUNNABLE : Int := 3
def PROC_STATE_RUNNING  : Int := 4
def PROC_STATE_ZOMBIE   : Int := 5

-- ============================================================================
-- 2. Stage L: Process Structure Memory Layout & Offsets
-- ============================================================================

/-- Byte offsets within `struct proc` (256 bytes per process) -/
def PROC_OFFSET_STATE     : Int := 0    -- uint64 state
def PROC_OFFSET_KILLED    : Int := 8    -- uint64 killed
def PROC_OFFSET_XSTATE    : Int := 16   -- uint64 exit state
def PROC_OFFSET_PID       : Int := 24   -- uint64 pid
def PROC_OFFSET_KSTACK    : Int := 32   -- uint64 kstack (4KB page address)
def PROC_OFFSET_SZ        : Int := 40   -- uint64 user memory size
def PROC_OFFSET_PAGETABLE : Int := 48   -- uint64 user page table pointer
def PROC_OFFSET_TRAPFRAME : Int := 56   -- uint64 trapframe pointer
def PROC_OFFSET_CONTEXT        : Int := 64   -- 112 bytes: struct context (ra, sp, s0..s11)
def PROC_OFFSET_NAME           : Int := 176  -- 16 bytes: process name string
def PROC_OFFSET_USER_CODE_PA   : Int := 192  -- uint64 user code physical page address (Page 0)
def PROC_OFFSET_USER_STACK_PA  : Int := 200  -- uint64 user stack physical page address (Page 1)

/-- Size of a single `struct proc` entry in bytes -/
def PROC_SIZE : Int := 256

/-- Byte offsets within `struct trapframe` (4096-byte page) -/
def TF_OFFSET_KERNEL_SATP   : Int := 0   -- uint64 kernel satp
def TF_OFFSET_KERNEL_SP     : Int := 8   -- uint64 kernel sp (top of kstack)
def TF_OFFSET_KERNEL_TRAP   : Int := 16  -- uint64 kernel usertrap function
def TF_OFFSET_EPC           : Int := 24  -- uint64 saved user program counter (sepc)
def TF_OFFSET_KERNEL_HARTID : Int := 32  -- uint64 kernel hartid
def TF_OFFSET_RA            : Int := 40
def TF_OFFSET_SP            : Int := 48
def TF_OFFSET_GP            : Int := 56
def TF_OFFSET_TP            : Int := 64
def TF_OFFSET_T0            : Int := 72
def TF_OFFSET_T1            : Int := 80
def TF_OFFSET_T2            : Int := 88
def TF_OFFSET_S0            : Int := 96
def TF_OFFSET_S1            : Int := 104
def TF_OFFSET_A0            : Int := 112
def TF_OFFSET_A1            : Int := 120
def TF_OFFSET_A2            : Int := 128
def TF_OFFSET_A3            : Int := 136
def TF_OFFSET_A4            : Int := 144
def TF_OFFSET_A5            : Int := 152
def TF_OFFSET_A6            : Int := 160
def TF_OFFSET_A7            : Int := 168
def TF_OFFSET_S2            : Int := 176
def TF_OFFSET_S3            : Int := 184
def TF_OFFSET_S4            : Int := 192
def TF_OFFSET_S5            : Int := 200
def TF_OFFSET_S6            : Int := 208
def TF_OFFSET_S7            : Int := 216
def TF_OFFSET_S8            : Int := 224
def TF_OFFSET_S9            : Int := 232
def TF_OFFSET_S10           : Int := 240
def TF_OFFSET_S11           : Int := 248
def TF_OFFSET_T3            : Int := 256
def TF_OFFSET_T4            : Int := 264
def TF_OFFSET_T5            : Int := 272
def TF_OFFSET_T6            : Int := 280

/-- Total size of the 64-entry process table (16384 bytes = 16KB) -/
def PROC_TABLE_TOTAL_BYTES : Nat := NPROC * 256

/-- Static process table holding 64 entries in .data -/
globalData procTable := do
  align 4 -- 16-byte aligned
  space PROC_TABLE_TOTAL_BYTES

/-- Global holding the next available process ID -/
globalData nextPid := do
  quad 1

/-- Temporary test context structures for coroutine switch verification -/
globalData testCtxOrigin := do
  align 4
  space 112

globalData testCtxTarget := do
  align 4
  space 112

-- ============================================================================
-- 3. Context Switch Subroutine (swtch)
-- ============================================================================

/-- Context switch subroutine: `swtch(struct context *old, struct context *new)`
    Spills caller's 14 callee-saved registers (ra, sp, s0..s11) into 0(a0)..104(a0),
    restores target's 14 registers from 0(a1)..104(a1), and resumes via ret.
-/
function swtch := do
  -- Save caller registers into old context (*a0)
  sd ra 0 a0
  sd sp 8 a0
  sd s0 16 a0
  sd s1 24 a0
  sd s2 32 a0
  sd s3 40 a0
  sd s4 48 a0
  sd s5 56 a0
  sd s6 64 a0
  sd s7 72 a0
  sd s8 80 a0
  sd s9 88 a0
  sd s10 96 a0
  sd s11 104 a0

  -- Restore target registers from new context (*a1)
  ld ra 0 a1
  ld sp 8 a1
  ld s0 16 a1
  ld s1 24 a1
  ld s2 32 a1
  ld s3 40 a1
  ld s4 48 a1
  ld s5 56 a1
  ld s6 64 a1
  ld s7 72 a1
  ld s8 80 a1
  ld s9 88 a1
  ld s10 96 a1
  ld s11 104 a1

  ret

-- ============================================================================
-- 4. Process Subsystem Initialization (procinit)
-- ============================================================================

/-- Initializes all 64 process slots, setting state to UNUSED and allocating
    a dedicated 4KB kernel stack page from `kalloc()` for each process.
-/
fn procinit () [ra s0 s1 s2 s3] := do
  la s0 procTable
  li s1 0           -- loop counter: 0..63
  li s2 NPROC       -- limit = 64
  li s3 PROC_SIZE   -- entry stride = 256

  let loopLbl ← freshLabel "procinit_loop"
  let endLbl  ← freshLabel "procinit_done"
  let panicLbl ← freshLabel "procinit_panic"

  label loopLbl
  bge s1 s2 endLbl

  -- Set state = UNUSED (0)
  sd zero PROC_OFFSET_STATE s0

  -- Set pid = 0
  sd zero PROC_OFFSET_PID s0

  -- Allocate 4KB kernel stack page for this process
  callFn kalloc []
  beqz a0 panicLbl

  -- Store allocated page address into p->kstack
  sd a0 PROC_OFFSET_KSTACK s0

  -- Advance to next process slot
  add s0 s0 s3
  addi s1 s1 1
  j loopLbl

  label panicLbl
  uartPrint "KERNEL PANIC: procinit failed to allocate kstack!\n"
  exitQemu 1
  let haltLbl ← freshLabel "halt"
  infiniteWait haltLbl

  label endLbl

-- ============================================================================
-- 5. Process Lifecycle Management (forkret, allocproc, freeproc)
-- ============================================================================

/-- Initial kernel execution routine for newly scheduled processes.
    Called when swtch switches into p->context.
-/
function forkret := do
  uartPrint "=== xv6-lean: forkret reached! Process 1 running on newly allocated kstack! ===\n"

  -- Read stack pointer to confirm it runs on Process 1 kstack
  mv a0 sp
  uartPrint "=== xv6-lean: Process 1 kstack pointer: "
  uartPrintHex a0
  uartPrint "\n"

  -- In our verification test, switch back to origin context to verify control return
  la a0 testCtxTarget
  la a1 testCtxOrigin
  call swtch

  infiniteSpin "forkret_spin"

/-- Allocates an UNUSED process slot, assigns a PID, allocates a trapframe page,
    and initializes context for execution with context.ra = forkret.
    Returns pointer to struct proc in a0, or 0 (NULL) on failure.
-/
fn allocproc () [ra s0 s1 s2 s3] := do
  la s0 procTable
  li s1 0           -- counter
  li s2 NPROC       -- 64
  li s3 PROC_SIZE   -- 256

  let loopLbl  ← freshLabel "alloc_loop"
  let foundLbl ← freshLabel "alloc_found"
  let oomLbl   ← freshLabel "alloc_oom"
  let doneLbl  ← freshLabel "alloc_done"

  label loopLbl
  bge s1 s2 oomLbl

  -- Check state == UNUSED (0)
  ld t0 PROC_OFFSET_STATE s0
  beqz t0 foundLbl

  -- Advance to next slot
  add s0 s0 s3
  addi s1 s1 1
  j loopLbl

  label foundLbl
  -- 1. Allocate next PID
  la t0 nextPid
  ld t1 0 t0
  sd t1 PROC_OFFSET_PID s0
  addi t1 t1 1
  sd t1 0 t0

  -- 2. Mark state as USED (1)
  li t0 PROC_STATE_USED
  sd t0 PROC_OFFSET_STATE s0

  -- 3. Allocate 4KB trapframe page via kalloc()
  callFn kalloc []
  beqz a0 oomLbl
  sd a0 PROC_OFFSET_TRAPFRAME s0

  -- 4. Set up context: context.ra = forkret
  la t0 forkret
  sd t0 (PROC_OFFSET_CONTEXT + 0) s0

  -- 5. Set up context: context.sp = kstack + 4096
  ld t0 PROC_OFFSET_KSTACK s0
  li t1 4096
  add t0 t0 t1
  sd t0 (PROC_OFFSET_CONTEXT + 8) s0

  -- 6. Zero callee-saved registers in context (s0..s11)
  sd zero (PROC_OFFSET_CONTEXT + 16) s0
  sd zero (PROC_OFFSET_CONTEXT + 24) s0
  sd zero (PROC_OFFSET_CONTEXT + 32) s0
  sd zero (PROC_OFFSET_CONTEXT + 40) s0
  sd zero (PROC_OFFSET_CONTEXT + 48) s0
  sd zero (PROC_OFFSET_CONTEXT + 56) s0
  sd zero (PROC_OFFSET_CONTEXT + 64) s0
  sd zero (PROC_OFFSET_CONTEXT + 72) s0
  sd zero (PROC_OFFSET_CONTEXT + 80) s0
  sd zero (PROC_OFFSET_CONTEXT + 88) s0
  sd zero (PROC_OFFSET_CONTEXT + 96) s0
  sd zero (PROC_OFFSET_CONTEXT + 104) s0

  -- Return allocated process pointer
  returnVal s0
  j doneLbl

  label oomLbl
  returnImm 0

  label doneLbl

/-- Frees a process structure, releasing its trapframe page via kfree
    and resetting its state to UNUSED.
-/
fn freeproc (p) [ra s0 s1] := do
  mv s0 p
  -- Read trapframe
  ld s1 PROC_OFFSET_TRAPFRAME s0
  let noTfLbl ← freshLabel "no_tf"
  beqz s1 noTfLbl

  -- kfree(p->trapframe)
  callFn kfree [s1]
  sd zero PROC_OFFSET_TRAPFRAME s0

  label noTfLbl
  -- Reclaim user code page if present
  ld s1 PROC_OFFSET_USER_CODE_PA s0
  let noCodeLbl ← freshLabel "no_code_page"
  beqz s1 noCodeLbl
  callFn kfree [s1]
  sd zero PROC_OFFSET_USER_CODE_PA s0

  label noCodeLbl
  -- Reclaim user stack page if present
  ld s1 PROC_OFFSET_USER_STACK_PA s0
  let noStackLbl ← freshLabel "no_stack_page"
  beqz s1 noStackLbl
  callFn kfree [s1]
  sd zero PROC_OFFSET_USER_STACK_PA s0

  label noStackLbl
  -- Reset pid = 0
  sd zero PROC_OFFSET_PID s0
  -- Reset state = UNUSED (0)
  sd zero PROC_OFFSET_STATE s0

-- ============================================================================
-- 6. In-Kernel Process Subsystem Verification (testProc)
-- ============================================================================

/-- Coroutine target entry function for swtch testing.
    Executes on Process 0's kernel stack, confirms execution, and switches back!
-/
function coroutineTestEntry := do
  uartPrint "=== xv6-lean: Coroutine test successfully switched into target thread! ===\n"

  -- Read current stack pointer to verify we are running on process stack
  mv a0 sp
  uartPrint "=== xv6-lean: Coroutine stack pointer: "
  uartPrintHex a0
  uartPrint "\n"

  -- Switch back to origin context!
  la a0 testCtxTarget
  la a1 testCtxOrigin
  call swtch
  -- We should not return past this point during test
  infiniteSpin "coroutine_spin"

/-- Comprehensive in-kernel test suite for process table, context switching,
    and process allocation lifecycle (allocproc, forkret, freeproc).
-/
fn testProc () [ra s0 s1 s2 s3] := do
  uartPrint "=== xv6-lean: Running Process Subsystem verification test suite... ===\n"

  -- 1. Verify all 64 process entries have UNUSED state and non-null kstack
  la s0 procTable
  li s1 0
  li s2 NPROC
  li s3 PROC_SIZE

  let verifyLoopLbl ← freshLabel "proc_verify_loop"
  let verifyDoneLbl ← freshLabel "proc_verify_done"
  let panicVerifyLbl ← freshLabel "proc_verify_fail"

  label verifyLoopLbl
  bge s1 s2 verifyDoneLbl

  -- Verify state == UNUSED (0)
  ld t0 PROC_OFFSET_STATE s0
  bnez t0 panicVerifyLbl

  -- Verify kstack != 0
  ld t1 PROC_OFFSET_KSTACK s0
  beqz t1 panicVerifyLbl

  -- Verify kstack alignment (t1 & 0xfff == 0)
  li t2 0xfff
  and_ t2 t1 t2
  bnez t2 panicVerifyLbl

  -- Advance
  add s0 s0 s3
  addi s1 s1 1
  j verifyLoopLbl

  label panicVerifyLbl
  uartPrint "KERNEL PANIC: testProc table verification failed!\n"
  exitQemu 1
  let haltLbl ← freshLabel "halt"
  infiniteWait haltLbl

  label verifyDoneLbl
  uartPrint "=== xv6-lean: Verified all 64 process slots initialized with valid 4KB kstacks! ===\n"

  -- 2. Test Context Switch (`swtch`):
  -- Initialize testCtxTarget:
  --   ra = coroutineTestEntry
  --   sp = procTable[0].kstack + 4096 (16-byte aligned top of stack)
  la s0 procTable
  ld s1 PROC_OFFSET_KSTACK s0
  li t0 4096
  add s1 s1 t0 -- s1 = kstack top

  la s2 testCtxTarget
  la t0 coroutineTestEntry
  sd t0 0 s2   -- target.ra = coroutineTestEntry
  sd s1 8 s2   -- target.sp = kstack top

  uartPrint "=== xv6-lean: Testing context switch (swtch) to coroutine... ===\n"

  -- Perform context switch: swtch(&testCtxOrigin, &testCtxTarget)
  la a0 testCtxOrigin
  la a1 testCtxTarget
  call swtch

  -- We expect to return here when coroutine switches back!
  uartPrint "=== xv6-lean: Successfully returned from context switch back to main thread! ===\n"

  -- 3. Test Process Allocation (allocproc) and First Process Context Switching
  uartPrint "=== xv6-lean: Testing allocproc() to create Process 1... ===\n"
  callFn allocproc []
  mv s0 a0 -- s0 = allocated struct proc*
  let panicAllocLbl ← freshLabel "alloc_fail"
  beqz s0 panicAllocLbl

  -- Verify pid != 0
  ld t0 PROC_OFFSET_PID s0
  beqz t0 panicAllocLbl

  -- Verify state == USED (1)
  ld t0 PROC_OFFSET_STATE s0
  li t1 PROC_STATE_USED
  bne t0 t1 panicAllocLbl

  -- Verify trapframe != 0
  ld t0 PROC_OFFSET_TRAPFRAME s0
  beqz t0 panicAllocLbl

  uartPrint "=== xv6-lean: allocproc() succeeded: PID, state=USED, trapframe valid! ===\n"

  -- Context switch into newly allocated process (p->context):
  -- s0 is process pointer; context starts at PROC_OFFSET_CONTEXT (64)
  addi s1 s0 PROC_OFFSET_CONTEXT
  la a0 testCtxOrigin
  mv a1 s1
  uartPrint "=== xv6-lean: Context-switching into Process 1 via swtch... ===\n"
  call swtch

  uartPrint "=== xv6-lean: Successfully returned from Process 1 back to main! ===\n"

  -- Now test freeproc(p)
  uartPrint "=== xv6-lean: Testing freeproc() to release Process 1... ===\n"
  callFn freeproc [s0]

  -- Verify state returned to UNUSED (0)
  ld t0 PROC_OFFSET_STATE s0
  bnez t0 panicAllocLbl

  -- Verify trapframe reset to 0
  ld t0 PROC_OFFSET_TRAPFRAME s0
  bnez t0 panicAllocLbl

  -- Verify pid reset to 0
  ld t0 PROC_OFFSET_PID s0
  bnez t0 panicAllocLbl

  uartPrint "=== xv6-lean: freeproc() cleanly reclaimed trapframe and reset process slot! ===\n"
  uartPrint "=== xv6-lean: ALL Process Subsystem & Lifecycle tests PASSED! ===\n"

  let endTestLbl ← freshLabel "test_done"
  j endTestLbl

  label panicAllocLbl
  uartPrint "KERNEL PANIC: allocproc/lifecycle verification failed!\n"
  exitQemu 1
  let haltLbl ← freshLabel "halt"
  infiniteWait haltLbl

  label endTestLbl

end LeanXv6.Proc
