import «LeanXv6».RiscV
import «LeanXv6».StageW

namespace LeanXv6.Kalloc

open LeanXv6.RiscV
open LeanXv6.StageW

/-!
# Physical Memory Page Allocator (Stage W & Low IR)
(Corresponds to Domain II in design/10-boot-dag-and-parallel-initialization.md
 and spec/kalloc.py)

Manages physical 4KB memory frames from `end` to `PHYSTOP` (0x88000000).
-/

-- Global head pointer of the intrusive free list (8 bytes in .data)
globalData kmem_freelist := do
  quad 0

-- PHYSTOP constant: 0x88000000 (128MB RAM boundary)
def phystopVal : Int := 0x88000000

/-- Frees a 4KB physical page, scrub-filling it with junk and pushing to kmem_freelist -/
fn kfree (pa) [ra s0 s1] := do
  -- 1. Validate page alignment: pa % 4096 == 0 (pa & 0xfff == 0)
  li t1 0xfff
  and_ t0 pa t1
  let alignOkLbl ← freshLabel "kfree_align_ok"
  let halt1Lbl ← freshLabel "panic_halt"
  beqz t0 alignOkLbl
  uartPrint "KERNEL PANIC: kfree unaligned address!\n"
  exitQemu 1
  infiniteWait halt1Lbl

  label alignOkLbl
  -- 2. Validate range: pa < PHYSTOP
  li t0 phystopVal
  let rangeOkLbl ← freshLabel "kfree_range_ok"
  let halt2Lbl ← freshLabel "panic_halt"
  bltu pa t0 rangeOkLbl
  uartPrint "KERNEL PANIC: kfree address exceeds PHYSTOP!\n"
  exitQemu 1
  infiniteWait halt2Lbl

  label rangeOkLbl
  -- 3. Scrub page: fill 512 quad words (4096 bytes) with junk pattern 0x0101010101010101
  li t0 0x0101010101010101
  li t1 512
  mv t2 pa
  let scrubLoopLbl ← freshLabel "scrub_loop"
  label scrubLoopLbl
  sd t0 0 t2
  addi t2 t2 8
  addi t1 t1 (-1)
  bnez t1 scrubLoopLbl

  -- 4. Push page onto head of kmem_freelist
  la t0 kmem_freelist
  ld t1 0 t0         -- t1 = old head
  sd t1 0 pa         -- pa->next = old head
  sd pa 0 t0         -- kmem_freelist = pa

/-- Allocates a 4KB physical page, zeroes its content, and returns address in a0 -/
fn kalloc () [ra s0 s1] := do
  la t0 kmem_freelist
  ld t1 0 t0         -- t1 = kmem_freelist
  let oomLbl ← freshLabel "kalloc_oom"
  beqz t1 oomLbl

  -- Pop head: kmem_freelist = head->next
  ld t2 0 t1
  sd t2 0 t0

  -- Zero the allocated page (512 words * 8 bytes = 4096 bytes)
  li t0 512
  mv t2 t1
  let zeroLoopLbl ← freshLabel "zero_loop"
  label zeroLoopLbl
  sd zero 0 t2
  addi t2 t2 8
  addi t0 t0 (-1)
  bnez t0 zeroLoopLbl

  -- Return allocated page address
  returnVal t1
  let doneLbl ← freshLabel "kalloc_done"
  j doneLbl

  label oomLbl
  -- Return NULL (0) on out of memory
  returnImm 0

  label doneLbl

/-- Sweeps memory from `end` to `PHYSTOP` in 4096-byte frames, calling kfree on each -/
fn kinit () [ra s0 s1 s2] := do
  -- Round up `end` to next 4096-byte page boundary
  la s0 "end"
  li t0 4095
  add s0 s0 t0
  li t0 (-4096)
  and_ s0 s0 t0

  -- s1 = PHYSTOP
  li s1 phystopVal
  li s2 4096

  let loopLbl ← freshLabel "kinit_loop"
  let endLbl ← freshLabel "kinit_end"

  label loopLbl
  bgeu s0 s1 endLbl
  callFn kfree [s0]
  add s0 s0 s2
  j loopLbl

  label endLbl

/-- In-kernel self-test verifying allocation, read/write, free, and LIFO recycling -/
fn testKalloc () [ra s0 s1 s2] := do
  -- Allocate page 1
  callFn kalloc []
  mv s0 a0
  let testFailLbl ← freshLabel "test_fail"
  beqz s0 testFailLbl

  -- Allocate page 2
  callFn kalloc []
  mv s1 a0
  beqz s1 testFailLbl

  -- Verify s0 != s1
  beq s0 s1 testFailLbl

  -- Write canary values
  li t0 0xdeadbeefcafebabe
  sd t0 0 s0
  sd t0 1024 s1

  -- Read back and verify
  ld t1 0 s0
  bne t0 t1 testFailLbl
  ld t1 1024 s1
  bne t0 t1 testFailLbl

  -- Free page 2
  callFn kfree [s1]

  -- Re-allocate page: LIFO free list must return s1!
  callFn kalloc []
  mv s2 a0
  bne s1 s2 testFailLbl

  -- Clean up page 1 and page 2
  callFn kfree [s0]
  callFn kfree [s2]

  uartPrint "=== xv6-lean: Physical page allocator (kinit/kalloc/kfree) verified successfully! ===\n"
  let doneLbl ← freshLabel "test_done"
  j doneLbl

  label testFailLbl
  uartPrint "KERNEL PANIC: testKalloc verification failed!\n"
  exitQemu 1
  let haltFailLbl ← freshLabel "panic_halt"
  infiniteWait haltFailLbl

  label doneLbl

end LeanXv6.Kalloc
