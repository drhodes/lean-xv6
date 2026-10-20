import «LeanXv6».RiscV
import «LeanXv6».StageW
import «LeanXv6».Kalloc
import «LeanXv6».Proc

namespace LeanXv6.Syscall

open LeanXv6.RiscV
open LeanXv6.StageW
open LeanXv6.Kalloc
open LeanXv6.Proc

/-!
# System Call Subsystem & Console I/O (Milestone 3)
Corresponds to Milestone 3 in the shell roadmap and spec/shell.py.

Provides standard POSIX-like system calls for User Mode (Ring 3):
- SYS_exit  (2): Terminate user process and return to kernel
- SYS_read  (5): Read characters from console UART into user buffer
- SYS_write (16): Write characters from user buffer to console UART
-/

-- ============================================================================
-- 1. System Call Numbers (Standard xv6-riscv ABI)
-- ============================================================================

def SYS_fork   : Int := 1
def SYS_exit   : Int := 2
def SYS_wait   : Int := 3
def SYS_read   : Int := 5
def SYS_kill   : Int := 6
def SYS_getpid : Int := 11
def SYS_write  : Int := 16

-- ============================================================================
-- 2. Console UART Device Drivers (Polled RX & TX)
-- ============================================================================

/-- Reads a single character from UART0 (blocking until a character is ready) -/
fn uartGetc () := do
  li t0 0x10000000
  let waitLbl ← freshLabel "uart_getc_wait"
  label waitLbl
  lb t1 5 t0 -- read Line Status Register (LSR)
  andi t1 t1 1 -- check Data Ready (DR) bit 0
  beqz t1 waitLbl
  lb a0 0 t0 -- read Receiver Buffer Register (RBR)
  returnVal a0

/-- Emits a single character to UART0 with automatic \r\n expansion -/
fn uartPutc (c) := do
  li t0 0x10000000
  li t1 10 -- '\n'
  let noCrLbl ← freshLabel "no_cr"
  bne c t1 noCrLbl
  li t2 13 -- '\r'
  sb t2 0 t0
  label noCrLbl
  sb c 0 t0

-- ============================================================================
-- 3. User Virtual Address Translation (uva2pa)
-- ============================================================================

/-- Translates user virtual address `uva` to physical address in kernel address space.
    Page 0 (0x0000..0x0fff): User Code & Constant Strings (RX)
    Page 1 (0x1000..0x1fff): User Data, Line Buffer & Stack (RW)
-/
fn uva2pa (p uva) [ra s0 s1] := do
  mv s0 p
  mv s1 uva
  li t0 0x1000
  let isStackLbl ← freshLabel "uva_stack"
  let doneLbl ← freshLabel "uva_done"
  bgeu s1 t0 isStackLbl
  -- Page 0: Code / Rodata
  ld t1 PROC_OFFSET_USER_CODE_PA s0
  add a0 t1 s1
  j doneLbl
  label isStackLbl
  -- Page 1: Data / Stack
  ld t1 PROC_OFFSET_USER_STACK_PA s0
  sub s1 s1 t0
  add a0 t1 s1
  label doneLbl

-- ============================================================================
-- 4. System Call Handlers
-- ============================================================================

/-- sys_write(p, fd, uva, count)
    Writes `count` bytes from user virtual memory buffer `uva` to console UART. -/
fn sys_write (p fd uva count) [ra s0 s1 s2 s3 s4] := do
  mv s0 p
  mv s1 fd
  mv s2 uva
  mv s3 count

  -- Translate user buffer to physical address in kernel space
  callFn uva2pa [s0, s2]
  mv s4 a0 -- s4 = physical address of buffer

  li s1 0 -- s1 = written count
  let loopLbl ← freshLabel "write_loop"
  let endLbl ← freshLabel "write_end"

  label loopLbl
  bge s1 s3 endLbl
  lb a0 0 s4
  callFn uartPutc [a0]
  addi s4 s4 1
  addi s1 s1 1
  j loopLbl

  label endLbl
  returnVal s1

/-- sys_read(p, fd, uva, max_len)
    Reads input line from console UART into user virtual memory buffer `uva`
    with terminal echoing, backspace handling, and newline termination. -/
fn sys_read (p fd uva max_len) [ra s0 s1 s2 s3 s4 s5] := do
  mv s0 p
  mv s1 fd
  mv s2 uva
  mv s3 max_len

  -- Translate user buffer to physical address in kernel space
  callFn uva2pa [s0, s2]
  mv s4 a0 -- s4 = physical pointer to user buffer

  li s5 0 -- s5 = bytes read count
  addi s3 s3 (-1) -- reserve 1 byte for null terminator

  let readLoopLbl ← freshLabel "read_loop"
  let isBsLbl ← freshLabel "read_bs"
  let isEnterLbl ← freshLabel "read_enter"
  let endLbl ← freshLabel "read_end"

  label readLoopLbl
  callFn uartGetc []
  -- a0 holds incoming byte

  -- Check for Backspace: 8 (\b) or 127 (DEL)
  li t0 8
  beq a0 t0 isBsLbl
  li t0 127
  beq a0 t0 isBsLbl

  -- Check for Enter: 10 (\n) or 13 (\r)
  li t0 10
  beq a0 t0 isEnterLbl
  li t0 13
  beq a0 t0 isEnterLbl

  -- Regular character: store if buffer has space
  bge s5 s3 readLoopLbl

  -- Store in user buffer
  sb a0 0 s4
  addi s4 s4 1
  addi s5 s5 1

  -- Echo character to console
  callFn uartPutc [a0]
  j readLoopLbl

  label isBsLbl
  -- Backspace: erase previous character if any
  beqz s5 readLoopLbl
  addi s4 s4 (-1)
  addi s5 s5 (-1)
  -- Echo \b \b to erase visually on screen
  li a0 8
  callFn uartPutc [a0]
  li a0 32 -- space
  callFn uartPutc [a0]
  li a0 8
  callFn uartPutc [a0]
  j readLoopLbl

  label isEnterLbl
  -- Echo newline to console
  li a0 10
  callFn uartPutc [a0]
  -- Null terminate buffer
  sb zero 0 s4
  j endLbl

  label endLbl
  returnVal s5

/-- sys_fork(p)
    Creates a new child process duplicating the parent's user memory and trapframe.
    Returns child PID in parent, and 0 in child.
-/
fn sys_fork (p) [ra s0 s1 s2 s3 s4 s5] := do
  mv s0 p -- s0 = parent struct proc*

  -- 1. Allocate child process slot
  callFn allocproc []
  let forkFailLbl ← freshLabel "fork_fail"
  beqz a0 forkFailLbl
  mv s1 a0 -- s1 = child struct proc* (np)

  -- 2. Allocate child Page 0 (Code/Rodata) and Page 1 (Stack/Data)
  callFn kalloc []
  let forkFailChildLbl ← freshLabel "fork_fail_child"
  beqz a0 forkFailChildLbl
  mv s2 a0 -- s2 = child code PA

  callFn kalloc []
  let forkFailCodeLbl ← freshLabel "fork_fail_code"
  beqz a0 forkFailCodeLbl
  mv s3 a0 -- s3 = child stack PA

  -- 3. Copy Page 0 from parent to child (512 quad words = 4096 bytes)
  ld s4 PROC_OFFSET_USER_CODE_PA s0
  mv s5 s2 -- child destination
  li t0 512
  let copyP0Lbl ← freshLabel "fork_copy_p0"
  let copyP0DoneLbl ← freshLabel "fork_copy_p0_done"
  label copyP0Lbl
  beqz t0 copyP0DoneLbl
  ld t1 0 s4
  sd t1 0 s5
  addi s4 s4 8
  addi s5 s5 8
  addi t0 t0 (-1)
  j copyP0Lbl
  label copyP0DoneLbl

  -- 4. Copy Page 1 from parent to child (512 quad words = 4096 bytes)
  ld s4 PROC_OFFSET_USER_STACK_PA s0
  mv s5 s3 -- child destination
  li t0 512
  let copyP1Lbl ← freshLabel "fork_copy_p1"
  let copyP1DoneLbl ← freshLabel "fork_copy_p1_done"
  label copyP1Lbl
  beqz t0 copyP1DoneLbl
  ld t1 0 s4
  sd t1 0 s5
  addi s4 s4 8
  addi s5 s5 8
  addi t0 t0 (-1)
  j copyP1Lbl
  label copyP1DoneLbl

  -- 5. Build child Sv39 user page table
  callFn "proc_pagetable" [s1, s2, s3]

  -- 6. Copy trapframe from parent to child (36 quad words = 288 bytes)
  ld s4 PROC_OFFSET_TRAPFRAME s0
  ld s5 PROC_OFFSET_TRAPFRAME s1
  li t0 36
  let copyTfLbl ← freshLabel "fork_copy_tf"
  let copyTfDoneLbl ← freshLabel "fork_copy_tf_done"
  label copyTfLbl
  beqz t0 copyTfDoneLbl
  ld t1 0 s4
  sd t1 0 s5
  addi s4 s4 8
  addi s5 s5 8
  addi t0 t0 (-1)
  j copyTfLbl
  label copyTfDoneLbl

  -- 7. In child's trapframe, set return value a0 = 0!
  ld s5 PROC_OFFSET_TRAPFRAME s1
  sd zero TF_OFFSET_A0 s5

  -- 8. Set parent-child relationship: child->parent = parent
  sd s0 PROC_OFFSET_PARENT s1

  -- 9. Mark child state as RUNNABLE (3)
  li t0 PROC_STATE_RUNNABLE
  sd t0 PROC_OFFSET_STATE s1

  -- 10. Parent returns child PID
  ld a0 PROC_OFFSET_PID s1
  returnVal a0
  let forkDoneLbl ← freshLabel "fork_done"
  j forkDoneLbl

  label forkFailCodeLbl
  callFn kfree [s2]
  label forkFailChildLbl
  callFn freeproc [s1]
  label forkFailLbl
  li a0 (-1)
  returnVal a0

  label forkDoneLbl

/-- sys_wait(p, uva_status)
    Scans procTable for children of p.
    If a child is ZOMBIE, extracts exit code, reclaims child via freeproc,
    and returns child PID.
    If no children exist, returns -1.
    If children exist but are still running, cooperatively yields to scheduler.
-/
fn sys_wait (p uva_status) [ra s0 s1 s2 s3 s4 s5 s6] := do
  mv s0 p
  mv s1 uva_status

  let waitRetryLbl ← freshLabel "wait_retry"
  label waitRetryLbl

  la s2 procTable  -- s2 = procTable scan pointer
  li s3 0          -- s3 = index counter (0..63)
  li s4 0          -- s4 = have_kids flag
  li s5 NPROC      -- 64
  li s6 PROC_SIZE  -- 256

  let scanLoopLbl ← freshLabel "wait_scan_loop"
  let nextProcLbl ← freshLabel "wait_next_proc"
  let checkKidsLbl ← freshLabel "wait_check_kids"
  let waitDoneLbl ← freshLabel "wait_done"

  label scanLoopLbl
  bge s3 s5 checkKidsLbl

  -- Check if slot is not UNUSED
  ld t0 PROC_OFFSET_STATE s2
  beqz t0 nextProcLbl

  -- Check if this process's parent is s0
  ld t1 PROC_OFFSET_PARENT s2
  bne t1 s0 nextProcLbl

  -- Child found! Set have_kids = 1
  li s4 1

  -- Check if child state == ZOMBIE (5)
  li t2 PROC_STATE_ZOMBIE
  bne t0 t2 nextProcLbl

  -- Found a ZOMBIE child!
  -- Read child PID
  ld s3 PROC_OFFSET_PID s2 -- s3 = child PID

  -- If uva_status != 0, write child exit status to user memory
  let skipStatusLbl ← freshLabel "wait_skip_status"
  beqz s1 skipStatusLbl
  callFn uva2pa [s0, s1]
  -- a0 is physical address of status in kernel space
  ld t3 PROC_OFFSET_XSTATE s2
  sd t3 0 a0
  label skipStatusLbl

  -- Reclaim child process resources
  callFn freeproc [s2]

  -- Return child PID in a0!
  returnVal s3
  j waitDoneLbl

  label nextProcLbl
  add s2 s2 s6
  addi s3 s3 1
  j scanLoopLbl

  label checkKidsLbl
  -- If have_kids == 0: no children! Return -1
  let hasKidsLbl ← freshLabel "wait_has_kids"
  bnez s4 hasKidsLbl
  li a0 (-1)
  returnVal a0
  j waitDoneLbl

  label hasKidsLbl
  -- Children exist but none are ZOMBIE yet!
  -- Yield CPU to scheduler:
  callFn yieldProcess [s0]

  -- Resumed by scheduler! Loop back and re-scan!
  j waitRetryLbl

  label waitDoneLbl

/-- sys_getpid(p)
    Returns current process PID.
-/
fn sys_getpid (p) := do
  ld a0 PROC_OFFSET_PID p
  returnVal a0

/-- sys_exit(p, status)
    Marks process state as ZOMBIE and records exit status code. -/
fn sys_exit (p status) [ra s0 s1] := do
  mv s0 p
  mv s1 status
  li t0 PROC_STATE_ZOMBIE
  sd t0 PROC_OFFSET_STATE s0
  sd s1 PROC_OFFSET_XSTATE s0
  returnVal zero

-- ============================================================================
-- 5. System Call Dispatcher (syscall)
-- ============================================================================

/-- Dispatches system calls from User Mode.
    Returns 1 if the process called SYS_exit, 0 otherwise. -/
fn syscall (p) [ra s0 s1 s2 s3 s4 s5] := do
  mv s0 p
  ld s1 PROC_OFFSET_TRAPFRAME s0
  ld s2 TF_OFFSET_A7 s1 -- syscall number in a7
  ld s3 TF_OFFSET_A0 s1 -- arg 0
  ld s4 TF_OFFSET_A1 s1 -- arg 1
  ld s5 TF_OFFSET_A2 s1 -- arg 2

  let notForkLbl ← freshLabel "not_fork"
  let notWaitLbl ← freshLabel "not_wait"
  let notReadLbl ← freshLabel "not_read"
  let notWriteLbl ← freshLabel "not_write"
  let notExitLbl ← freshLabel "not_exit"
  let notGetpidLbl ← freshLabel "not_getpid"
  let doneLbl ← freshLabel "syscall_done"

  -- 1. SYS_fork (1)
  li t0 SYS_fork
  bne s2 t0 notForkLbl
  callFn sys_fork [s0]
  sd a0 TF_OFFSET_A0 s1 -- store return value in trapframe->a0
  returnImm 0
  j doneLbl

  label notForkLbl
  -- 2. SYS_exit (2)
  li t0 SYS_exit
  bne s2 t0 notExitLbl
  callFn sys_exit [s0, s3]
  sd a0 TF_OFFSET_A0 s1
  returnImm 1 -- Signal process exit to usertrap!
  j doneLbl

  label notExitLbl
  -- 3. SYS_wait (3)
  li t0 SYS_wait
  bne s2 t0 notWaitLbl
  callFn sys_wait [s0, s3]
  sd a0 TF_OFFSET_A0 s1
  returnImm 0
  j doneLbl

  label notWaitLbl
  -- 4. SYS_read (5)
  li t0 SYS_read
  bne s2 t0 notReadLbl
  callFn sys_read [s0, s3, s4, s5]
  sd a0 TF_OFFSET_A0 s1
  returnImm 0
  j doneLbl

  label notReadLbl
  -- 5. SYS_getpid (11)
  li t0 SYS_getpid
  bne s2 t0 notGetpidLbl
  callFn sys_getpid [s0]
  sd a0 TF_OFFSET_A0 s1
  returnImm 0
  j doneLbl

  label notGetpidLbl
  -- 6. SYS_write (16)
  li t0 SYS_write
  bne s2 t0 notWriteLbl
  callFn sys_write [s0, s3, s4, s5]
  sd a0 TF_OFFSET_A0 s1
  returnImm 0
  j doneLbl

  label notWriteLbl
  -- Unknown syscall
  uartPrint "KERNEL WARNING: Unknown syscall number: "
  uartPrintHex s2
  uartPrint "\n"
  li a0 (-1)
  sd a0 TF_OFFSET_A0 s1
  returnImm 0

  label doneLbl

end LeanXv6.Syscall
