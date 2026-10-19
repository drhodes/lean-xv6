import «LeanXv6».RiscV
import «LeanXv6».StageW
import «LeanXv6».Kalloc
import «LeanXv6».Proc
import «LeanXv6».User
import «LeanXv6».Syscall

namespace LeanXv6.Shell

open LeanXv6.RiscV
open LeanXv6.StageW
open LeanXv6.Kalloc
open LeanXv6.Proc
open LeanXv6.User
open LeanXv6.Syscall

/-!
# Minimal Interactive User-Mode Shell (Milestone 4)
Corresponds to `spec/shell.py`:
- `ShellSubsystemReq`
- `UserShellExecutionFeat`

Executes in User Mode (Ring 3) backed by Sv39 virtual memory isolation
with strict $W \oplus X$ enforcement:
- User Virtual Page 0 (0x00000000 .. 0x00000fff): Code & Rodata (RX)
- User Virtual Page 1 (0x00001000 .. 0x00001fff): Stack & Line Buffer (RW)

All communication flows via standard RISC-V POSIX-like system calls:
- `SYS_read`  (5)
- `SYS_write` (16)
- `SYS_exit`  (2)
-/

-- ============================================================================
-- 1. User-Space Shell Binary Image (Page 0: Code & Rodata)
-- ============================================================================

/-- 4KB-aligned user-space binary image containing the shell code and strings.
    Assembled as position-independent code (PIC) with local PC-relative addressing.
-/
def shell_image : AsmM Unit := do
  section_ .rodata
  align 12 -- 4KB page alignment
  globl "shell_image_start"
  label "shell_image_start"
  emitRaw ".option push"
  emitRaw ".option norelax"

  -- User Entry Point at offset 0x00000000
  globl "_shell_entry"
  label "_shell_entry"
  -- 1. Initialize user stack pointer to top of Page 1 (0x1ff0, 16-byte aligned)
  li sp 0x1ff0

  -- 2. Print welcome banner
  lla a0 "shell_banner"
  jal ra "print_str"

  -- 3. Shell Main Loop
  label "shell_loop"
  -- Print prompt
  lla a0 "shell_prompt"
  jal ra "print_str"

  -- Read command line from console into Page 1 line buffer (0x1000)
  li a7 SYS_read
  li a0 0      -- stdin
  li a1 0x1000 -- buffer VA in Page 1
  li a2 128    -- max length
  ecall

  -- Check if empty input (Enter on empty line or EOF)
  beqz a0 "shell_loop"

  -- Command: help
  li a0 0x1000
  lla a1 "cmd_help"
  jal ra "strcmp"
  beqz a0 "do_help"

  -- Command: info
  li a0 0x1000
  lla a1 "cmd_info"
  jal ra "strcmp"
  beqz a0 "do_info"

  -- Command: clear
  li a0 0x1000
  lla a1 "cmd_clear"
  jal ra "strcmp"
  beqz a0 "do_clear"

  -- Command: exit
  li a0 0x1000
  lla a1 "cmd_exit"
  jal ra "strcmp"
  beqz a0 "do_exit"

  -- Command: echo
  li t0 0x1000
  lb t1 0 t0 -- 'e' (101)
  li t2 101
  bne t1 t2 "do_unknown"
  lb t1 1 t0 -- 'c' (99)
  li t2 99
  bne t1 t2 "do_unknown"
  lb t1 2 t0 -- 'h' (104)
  li t2 104
  bne t1 t2 "do_unknown"
  lb t1 3 t0 -- 'o' (111)
  li t2 111
  bne t1 t2 "do_unknown"
  lb t1 4 t0 -- next char: '\0' or ' '
  beqz t1 "echo_empty"
  li t2 32 -- ' '
  bne t1 t2 "do_unknown"
  -- Print echo arguments starting at offset 5 (0x1005)
  li a0 0x1005
  jal ra "print_str"
  label "echo_empty"
  lla a0 "newline_str"
  jal ra "print_str"
  j "shell_loop"

  -- ========================================================================
  -- Command Handlers
  -- ========================================================================

  label "do_help"
  lla a0 "help_msg"
  jal ra "print_str"
  j "shell_loop"

  label "do_info"
  lla a0 "info_msg"
  jal ra "print_str"
  j "shell_loop"

  label "do_clear"
  lla a0 "clear_seq"
  jal ra "print_str"
  j "shell_loop"

  label "do_exit"
  lla a0 "exit_msg"
  jal ra "print_str"
  li a7 SYS_exit
  li a0 0
  ecall
  label "shell_spin"
  j "shell_spin"

  label "do_unknown"
  lla a0 "unknown_prefix"
  jal ra "print_str"
  li a0 0x1000
  jal ra "print_str"
  lla a0 "unknown_suffix"
  jal ra "print_str"
  j "shell_loop"

  -- ========================================================================
  -- User Subroutines (Executed in Ring 3)
  -- ========================================================================

  -- Prints null-terminated string at user VA in a0 to stdout
  label "print_str"
  addi sp sp (-16)
  sd ra 8 sp
  sd a0 0 sp
  jal ra "strlen"
  mv a2 a0 -- length
  ld a1 0 sp -- buffer UVA
  li a0 1    -- stdout fd
  li a7 SYS_write
  ecall
  ld ra 8 sp
  addi sp sp 16
  ret

  -- Computes length of null-terminated string at user VA in a0 -> a0
  label "strlen"
  mv t0 a0
  label "strlen_loop"
  lb t1 0 t0
  beqz t1 "strlen_done"
  addi t0 t0 1
  j "strlen_loop"
  label "strlen_done"
  sub a0 t0 a0
  ret

  -- Compares null-terminated strings at a0 and a1. Returns 0 on match.
  label "strcmp"
  label "strcmp_loop"
  lb t0 0 a0
  lb t1 0 a1
  bne t0 t1 "strcmp_diff"
  beqz t0 "strcmp_match"
  addi a0 a0 1
  addi a1 a1 1
  j "strcmp_loop"
  label "strcmp_diff"
  sub a0 t0 t1
  ret
  label "strcmp_match"
  li a0 0
  ret

  -- ========================================================================
  -- Shell String Constants (Stored in Page 0 Rodata)
  -- ========================================================================

  label "shell_banner"
  asciz "\\n============================================================\\n            Welcome to xv6-lean Interactive Shell!          \\n  Architecture: RISC-V 64-bit (Ring 3 User Mode, Sv39 MMU)  \\n  Type 'help' for available commands.                       \\n============================================================\\n\\n"

  label "shell_prompt"
  asciz "xv6$ "

  label "cmd_help"
  asciz "help"

  label "cmd_info"
  asciz "info"

  label "cmd_clear"
  asciz "clear"

  label "cmd_exit"
  asciz "exit"

  label "help_msg"
  asciz "xv6-lean Shell Builtin Commands:\\n  help        - Display this help message\\n  info        - Display system architecture and memory status\\n  echo <text> - Print arguments to standard output\\n  clear       - Clear the terminal screen\\n  exit        - Terminate shell and cleanly return to kernel\\n"

  label "info_msg"
  asciz "System Architecture Information:\\n  OS: xv6-lean (Formally Typed MIT xv6 in Lean 4)\\n  Target: RISC-V RV64GC (QEMU virt)\\n  Execution Mode: Ring 3 User Mode (U-mode)\\n  Paging: Sv39 3-level page tables with W^X enforcement\\n  Syscalls: SYS_exit (2), SYS_read (5), SYS_write (16)\\n"

  label "clear_seq"
  asciz "\\033[2J\\033[H"

  label "exit_msg"
  asciz "Exiting shell. Goodbye!\\n"

  label "unknown_prefix"
  asciz "Unknown command: '"

  label "unknown_suffix"
  asciz "'. Type 'help' for available commands.\\n"

  label "newline_str"
  asciz "\\n"

  align 3
  globl "shell_image_end"
  label "shell_image_end"
  emitRaw ".option pop"

-- ============================================================================
-- 2. Kernel Shell Process Launcher (launchShell)
-- ============================================================================

/-- Allocates a new user process, copies shell_image to Page 0, maps Sv39
    isolated user page tables, and context-switches to User Mode (Ring 3). -/
fn launchShell () [ra s0 s1 s2 s3 s4 s5] := do
  uartPrint "=== xv6-lean: Launching User Mode Interactive Shell (Ring 3)... ===\n"

  -- 1. Allocate a process slot
  callFn allocproc []
  mv s0 a0 -- s0 = struct proc*

  -- Store as active process
  la t0 activeProc
  sd s0 0 t0

  -- 2. Allocate Page 0 (user code) and Page 1 (user stack/data)
  callFn kalloc []
  mv s1 a0 -- s1 = user code physical address

  callFn kalloc []
  mv s2 a0 -- s2 = user stack physical address

  -- 3. Copy shell_image to user code physical page (s1)
  la s3 "shell_image_start"
  la s4 "shell_image_end"
  mv s5 s1

  let copyLoopLbl ← freshLabel "shell_copy_loop"
  let copyDoneLbl ← freshLabel "shell_copy_done"
  label copyLoopLbl
  bgeu s3 s4 copyDoneLbl
  ld t0 0 s3
  sd t0 0 s5
  addi s3 s3 8
  addi s5 s5 8
  j copyLoopLbl
  label copyDoneLbl

  -- 4. Build Sv39 user page table:
  -- Page 0 (0x00000000): RX, PTE_U (Code & Rodata)
  -- Page 1 (0x00001000): RW, PTE_U (Stack & Line Buffer)
  callFn proc_pagetable [s0, s1, s2]

  -- 5. Set initial user registers in trapframe:
  ld t0 PROC_OFFSET_TRAPFRAME s0
  sd zero TF_OFFSET_EPC t0 -- epc := 0x00000000 (entry point)
  li t1 0x1ff0
  sd t1 TF_OFFSET_SP t0 -- sp := 0x00001ff0 (Page 1 top stack)

  -- 6. Switch execution into runUserThread -> usertrapret -> User Mode (Ring 3)
  la s3 testCtxTarget
  la t0 runUserThread
  sd t0 0 s3
  sd sp 8 s3

  la a0 testCtxOrigin
  la a1 testCtxTarget
  call swtch

  -- Re-acquired control after shell process calls SYS_exit!
  uartPrint "=== xv6-lean: Interactive Shell exited. Reclaiming process resources... ===\n"

  -- 7. Clean up process slot and reclaim physical pages
  callFn freeproc [s0]
  uartPrint "=== xv6-lean: Shell process cleanly reclaimed. Kernel execution finished! ===\n"

  returnImm 0

end LeanXv6.Shell
