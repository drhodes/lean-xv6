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

def SYS_exit  : Int := 2
def SYS_read  : Int := 5
def SYS_write : Int := 16

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
  ld s3 TF_OFFSET_A0 s1 -- arg 0 (fd / status)
  ld s4 TF_OFFSET_A1 s1 -- arg 1 (uva)
  ld s5 TF_OFFSET_A2 s1 -- arg 2 (count / max_len)

  let notReadLbl ← freshLabel "not_read"
  let notWriteLbl ← freshLabel "not_write"
  let notExitLbl ← freshLabel "not_exit"
  let doneLbl ← freshLabel "syscall_done"

  -- 1. SYS_write (16)
  li t0 SYS_write
  bne s2 t0 notWriteLbl
  callFn sys_write [s0, s3, s4, s5]
  sd a0 TF_OFFSET_A0 s1 -- store return value in trapframe->a0
  returnImm 0
  j doneLbl

  label notWriteLbl
  -- 2. SYS_read (5)
  li t0 SYS_read
  bne s2 t0 notReadLbl
  callFn sys_read [s0, s3, s4, s5]
  sd a0 TF_OFFSET_A0 s1 -- store return value in trapframe->a0
  returnImm 0
  j doneLbl

  label notReadLbl
  -- 3. SYS_exit (2)
  li t0 SYS_exit
  bne s2 t0 notExitLbl
  callFn sys_exit [s0, s3]
  sd a0 TF_OFFSET_A0 s1
  returnImm 1 -- Signal process exit to usertrap!
  j doneLbl

  label notExitLbl
  -- Unknown syscall
  uartPrint "KERNEL WARNING: Unknown syscall number: "
  uartPrintHex s2
  uartPrint "\n"
  li a0 (-1)
  sd a0 TF_OFFSET_A0 s1
  returnImm 0

  label doneLbl

end LeanXv6.Syscall
