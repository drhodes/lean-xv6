import «LeanXv6».RiscV
import «LeanXv6».StageW
import «LeanXv6».Kalloc
import «LeanXv6».Trap
import «LeanXv6».Proc
import «LeanXv6».Syscall

namespace LeanXv6.User

open LeanXv6.RiscV
open LeanXv6.StageW
open LeanXv6.Kalloc
open LeanXv6.Trap
open LeanXv6.Proc
open LeanXv6.Syscall

/-!
# User Mode Transition & Trampoline Subsystem (Milestone 2)
Corresponds to Milestone 2 in the shell roadmap and spec/user.py.

Provides the dual-mapped trampoline page (`uservec` and `userret`),
per-process multi-level Sv39 user page table construction,
user trap dispatching (`usertrap`), and privilege dropping (`sret`).
-/

-- ============================================================================
-- 1. Virtual Address Constants
-- ============================================================================

/-- Virtual address of the Trampoline page in both user and kernel address spaces -/
def TRAMPOLINE_VA : UInt64 := 0x3ffffff000

/-- Virtual address of the Trapframe page in user address space -/
def TRAPFRAME_VA  : UInt64 := 0x3fffffe000

/-- Physical address of _trampoline as mapped in kernel.ld (0x80010000) -/
def TRAMPOLINE_PA : UInt64 := 0x80010000

/-- Currently active user process pointer -/
globalData activeProc := do
  quad 0

-- ============================================================================
-- 2. The Trampoline Page (uservec and userret in .section trampsec)
-- ============================================================================

/-- Emits the 4KB trampoline page containing uservec and userret.
    Placed at physical address 0x80010000 in trampsec, and mapped at
    virtual address 0x3ffffff000 in both kernel and user page tables.
-/
def trampolineBlock : AsmM Unit := do
  trampoline
  align 12
  globl "_trampoline"
  label "_trampoline"

  globl "uservec"
  label "uservec"
  -- 1. Swap user a0 and sscratch (sscratch holds TRAPFRAME pointer 0x3fffffe000)
  csrrw a0 .sscratch a0

  -- 2. Save all user registers into TRAPFRAME (*a0)
  sd ra 40 a0
  sd sp 48 a0
  sd gp 56 a0
  sd tp 64 a0
  sd t0 72 a0
  sd t1 80 a0
  sd t2 88 a0
  sd s0 96 a0
  sd s1 104 a0
  sd a1 120 a0
  sd a2 128 a0
  sd a3 136 a0
  sd a4 144 a0
  sd a5 152 a0
  sd a6 160 a0
  sd a7 168 a0
  sd s2 176 a0
  sd s3 184 a0
  sd s4 192 a0
  sd s5 200 a0
  sd s6 208 a0
  sd s7 216 a0
  sd s8 224 a0
  sd s9 232 a0
  sd s10 240 a0
  sd s11 248 a0
  sd t3 256 a0
  sd t4 264 a0
  sd t5 272 a0
  sd t6 280 a0

  -- 3. Save original user a0 (which was swapped into sscratch)
  csrr t0 .sscratch
  sd t0 112 a0

  -- 4. Save user PC (sepc) into trapframe->epc
  csrr t1 .sepc
  sd t1 24 a0

  -- 5. Restore kernel context from trapframe
  ld sp 8 a0         -- kernel_sp
  ld tp 32 a0        -- kernel_hartid
  ld t0 16 a0        -- kernel_trap (usertrap)
  ld t1 0 a0         -- kernel_satp

  -- 6. Switch to kernel page table
  csrw .satp t1
  sfence_vma

  -- 7. Jump to usertrap()
  jr t0

  globl "userret"
  label "userret"
  -- userret(trapframe_va, user_satp)
  -- a0 = TRAPFRAME_VA (0x3fffffe000)
  -- a1 = user satp

  -- 1. Switch to user page table
  csrw .satp a1
  sfence_vma

  -- 2. Put saved user a0 into sscratch for the next uservec swap
  ld t0 112 a0
  csrw .sscratch t0

  -- 3. Restore user registers from TRAPFRAME (*a0)
  ld ra 40 a0
  ld sp 48 a0
  ld gp 56 a0
  ld tp 64 a0
  ld t0 72 a0
  ld t1 80 a0
  ld t2 88 a0
  ld s0 96 a0
  ld s1 104 a0
  -- a0 is in sscratch
  ld a1 120 a0
  ld a2 128 a0
  ld a3 136 a0
  ld a4 144 a0
  ld a5 152 a0
  ld a6 160 a0
  ld a7 168 a0
  ld s2 176 a0
  ld s3 184 a0
  ld s4 192 a0
  ld s5 200 a0
  ld s6 208 a0
  ld s7 216 a0
  ld s8 224 a0
  ld s9 232 a0
  ld s10 240 a0
  ld s11 248 a0
  ld t3 256 a0
  ld t4 264 a0
  ld t5 272 a0
  ld t6 280 a0

  -- 4. Restore user a0, placing TRAPFRAME back into sscratch
  csrrw a0 .sscratch a0

  -- 5. Drop privilege to User Mode and jump to sepc!
  sret

-- ============================================================================
-- 3. User Page Table Construction (proc_pagetable)
-- ============================================================================

/-- Constructs an Sv39 user page table for process `p`, mapping:
    - TRAMPOLINE at 0x3ffffff000 -> 0x80010000 (PTE_V | PTE_R | PTE_X | PTE_G | PTE_A)
    - TRAPFRAME at 0x3fffffe000 -> p->trapframe (PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
    - User Page 0 at 0x00000000 -> user_code_pa (PTE_V | PTE_R | PTE_X | PTE_U | PTE_A)
    - User Page 1 at 0x00001000 -> user_stack_pa (PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D)
    Returns root L2 table address in a0.
-/
fn proc_pagetable (p user_code_pa user_stack_pa) [ra s0 s1 s2 s3 s4 s5 s6 s7] := do
  mv s0 p
  mv s1 user_code_pa
  mv s7 user_stack_pa

  -- Record user pages in struct proc
  sd s1 PROC_OFFSET_USER_CODE_PA s0
  sd s7 PROC_OFFSET_USER_STACK_PA s0

  -- Allocate 5 page table pages:
  -- s2 = L2 root
  callFn kalloc []
  mv s2 a0

  -- s3 = L1 high (VPN[2] = 511)
  callFn kalloc []
  mv s3 a0

  -- s4 = L0 high (VPN[1] = 511)
  callFn kalloc []
  mv s4 a0

  -- s5 = L1 low (VPN[2] = 0)
  callFn kalloc []
  mv s5 a0

  -- s6 = L0 low (VPN[1] = 0)
  callFn kalloc []
  mv s6 a0

  -- 1. Link L2[255] -> L1 high: ((s3 >> 12) << 10) | 1 (PTE_V)
  srli t1 s3 12
  slli t1 t1 10
  ori  t1 t1 1
  li   t0 (255 * 8)
  add  t0 s2 t0
  sd   t1 0 t0

  -- 2. Link L1 high[511] -> L0 high: ((s4 >> 12) << 10) | 1 (PTE_V)
  srli t1 s4 12
  slli t1 t1 10
  ori  t1 t1 1
  li   t0 (511 * 8)
  add  t0 s3 t0
  sd   t1 0 t0

  -- 3. Populate L0 high[511] (TRAMPOLINE):
  -- Physical address 0x80010000 -> PPN 0x80010
  -- PTE = (0x80010 << 10) | 0x6b (V | R | X | G | A = 107)
  li   t1 0x80010
  slli t1 t1 10
  ori  t1 t1 0x6b
  li   t0 (511 * 8)
  add  t0 s4 t0
  sd   t1 0 t0

  -- 4. Populate L0 high[510] (TRAPFRAME):
  -- Physical address p->trapframe
  -- PTE = (trapframe_pa >> 12 << 10) | 0xc7 (V | R | W | A | D = 199)
  ld   t1 PROC_OFFSET_TRAPFRAME s0
  srli t1 t1 12
  slli t1 t1 10
  ori  t1 t1 0xc7
  li   t0 (510 * 8)
  add  t0 s4 t0
  sd   t1 0 t0

  -- 5. Link L2[0] -> L1 low: ((s5 >> 12) << 10) | 1 (PTE_V)
  srli t1 s5 12
  slli t1 t1 10
  ori  t1 t1 1
  sd   t1 0 s2

  -- 6. Link L1 low[0] -> L0 low: ((s6 >> 12) << 10) | 1 (PTE_V)
  srli t1 s6 12
  slli t1 t1 10
  ori  t1 t1 1
  sd   t1 0 s5

  -- 7. Populate L0 low[0] (User Code/Rodata at VA 0x00000000):
  -- Physical address user_code_pa
  -- PTE = (user_code_pa >> 12 << 10) | 0x5b (V | R | X | U | A = 91)
  srli t1 s1 12
  slli t1 t1 10
  ori  t1 t1 0x5b
  sd   t1 0 s6

  -- 8. Populate L0 low[1] (User Stack/Data at VA 0x00001000):
  -- Physical address user_stack_pa
  -- PTE = (user_stack_pa >> 12 << 10) | 0xd7 (V | R | W | U | A | D = 215)
  srli t1 s7 12
  slli t1 t1 10
  ori  t1 t1 0xd7
  sd   t1 8 s6

  -- Store root table into p->pagetable
  sd s2 PROC_OFFSET_PAGETABLE s0

  returnVal s2

-- ============================================================================
-- 4. Return to User Mode (usertrapret)
-- ============================================================================

/-- Prepares hardware registers and jumps to userret in the Trampoline page,
    dropping CPU privilege into User Mode (U-mode).
-/
fn usertrapret (p) [ra s0 s1 s2] := do
  mv s0 p
  ld s1 PROC_OFFSET_TRAPFRAME s0

  -- 1. Install uservec as supervisor trap vector (stvec := TRAMPOLINE_VA)
  li t0 0x3ffffff000
  csrw .stvec t0

  -- 2. Fill in trapframe kernel context
  csrr t0 .satp
  sd   t0 TF_OFFSET_KERNEL_SATP s1

  ld   t0 PROC_OFFSET_KSTACK s0
  li   t1 4096
  add  t0 t0 t1
  sd   t0 TF_OFFSET_KERNEL_SP s1

  la   t0 "usertrap"
  sd   t0 TF_OFFSET_KERNEL_TRAP s1

  sd   tp TF_OFFSET_KERNEL_HARTID s1

  -- 3. Set sstatus: clear SPP (bit 8 = 0, User mode), set SPIE (bit 5 = 1)
  csrr t0 .sstatus
  li   t1 0x100 -- bit 8
  xori t1 t1 (-1)
  and_ t0 t0 t1
  li   t1 0x20  -- bit 5
  or_  t0 t0 t1
  csrw .sstatus t0

  -- 4. Set sepc = trapframe->epc
  ld   t0 TF_OFFSET_EPC s1
  csrw .sepc t0

  -- 5. Prepare arguments for userret:
  -- a0: TRAPFRAME_VA (0x3fffffe000)
  li   a0 0x3fffffe000

  -- a1: user satp = (8 << 60) | (p->pagetable >> 12)
  ld   t0 PROC_OFFSET_PAGETABLE s0
  srli t0 t0 12
  li   t1 8
  slli t1 t1 60
  or_  a1 t0 t1

  -- 6. Jump to userret in Trampoline page
  la   t0 "userret"
  la   t1 "_trampoline"
  sub  t0 t0 t1
  li   t1 0x3ffffff000
  add  t0 t0 t1
  jr   t0

-- ============================================================================
-- 5. User Trap Dispatcher (usertrap)
-- ============================================================================

/-- Handles traps and system calls returning from User Mode. -/
function usertrap := do
  -- Read scause to verify it was an environment call (ecall, scause = 8)
  csrr t0 .scause
  li   t1 8
  let unexpectedLbl ← freshLabel "unexpected_trap"
  bne  t0 t1 unexpectedLbl

  -- Read active process pointer and trapframe
  la   t0 activeProc
  ld   s0 0 t0
  ld   s1 PROC_OFFSET_TRAPFRAME s0

  -- Advance epc past the 4-byte ecall instruction
  ld   t0 TF_OFFSET_EPC s1
  addi t0 t0 4
  sd   t0 TF_OFFSET_EPC s1

  -- Dispatch system call
  callFn syscall [s0]
  -- a0 is 1 if process called SYS_exit, 0 otherwise
  let continueLbl ← freshLabel "continue_user"
  beqz a0 continueLbl

  uartPrint "=== xv6-lean: User Mode process terminated via SYS_exit! ===\n"

  -- Reinstall kernelvec for supervisor traps
  installKernelTrap

  -- Switch back to caller context
  la a0 testCtxTarget
  la a1 testCtxOrigin
  call swtch
  infiniteSpin "usertrap_spin"

  label continueLbl
  -- Resume user execution via usertrapret!
  mv a0 s0
  call usertrapret

  label unexpectedLbl
  uartPrint "KERNEL PANIC: Unexpected trap from User Mode!\n"
  printTrapDiagnostics
  exitQemu 1
  let haltLbl ← freshLabel "halt"
  infiniteWait haltLbl

-- ============================================================================
-- 6. User Mode Execution Verification (testUser)
-- ============================================================================

/-- Intermediate trampoline that launches usertrapret in a separate thread context -/
function runUserThread := do
  la   t0 activeProc
  ld   a0 0 t0
  call usertrapret
  infiniteSpin "runUser_spin"

/-- Comprehensive in-kernel verification test for User Mode transition -/
fn testUser () [ra s0 s1 s2 s3] := do
  uartPrint "=== xv6-lean: Running User Mode (Ring 3) verification test suite... ===\n"

  -- 1. Allocate process slot
  callFn allocproc []
  mv s0 a0 -- s0 = struct proc*

  -- Store as active process
  la t0 activeProc
  sd s0 0 t0

  -- 2. Allocate Page 0 (user code) and Page 1 (user stack)
  callFn kalloc []
  mv s1 a0 -- s1 = user code physical address

  callFn kalloc []
  mv s2 a0 -- s2 = user stack physical address

  -- 3. Write test user program calling SYS_write then SYS_exit:
  li t0 0x0010051301000893
  sd t0 0 s1
  li t0 0x01e0061303000593 -- a2 = 30
  sd t0 8 s1
  li t0 0x0020089300000073
  sd t0 16 s1
  li t0 0x0000007300000513
  sd t0 24 s1
  li t0 0x0000006f
  sd t0 32 s1

  -- String at offset 48 (0x30): "User Mode SYS_write verified!\n"
  li t0 0x646f4d2072657355
  sd t0 48 s1
  li t0 0x72775f5359532065
  sd t0 56 s1
  li t0 0x6972657620657469
  sd t0 64 s1
  li t0 0x00000a2164656966
  sd t0 72 s1

  -- 4. Build user page table mapping TRAMPOLINE, TRAPFRAME, Code (Page 0), and Stack (Page 1)
  callFn proc_pagetable [s0, s1, s2]

  -- 5. Set user entry point: epc = 0x00000000
  ld s2 PROC_OFFSET_TRAPFRAME s0
  sd zero TF_OFFSET_EPC s2

  uartPrint "=== xv6-lean: Dropping CPU privilege from Supervisor to User Mode (Ring 3)... ===\n"

  -- 6. Switch execution into runUserThread
  la s3 testCtxTarget
  la t0 runUserThread
  sd t0 0 s3
  sd sp 8 s3

  la a0 testCtxOrigin
  la a1 testCtxTarget
  call swtch

  -- Re-acquired control after User Mode completes all ecalls!
  uartPrint "=== xv6-lean: Returned from User Mode back to kernel main thread! ===\n"
  uartPrint "=== xv6-lean: User Mode Execution & Trampoline Round-Trip VERIFIED! ===\n"

  -- 7. Clean up process
  callFn freeproc [s0]

end LeanXv6.User
