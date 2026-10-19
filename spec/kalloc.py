'''
Specifications for the lean-xv6 Physical Page Allocator (kinit, kalloc, kfree)
(Corresponds to Domain II in design/10-boot-dag-and-parallel-initialization.md)
'''

from .err import Feat, Req

class PhysicalPageAllocatorReq(Req):
    '''The operating system shall provide a physical memory page allocator
    (kinit, kalloc, kfree) managing all available 4KB physical RAM frames
    between the kernel symbol `end` and `PHYSTOP` (0x88000000).
    '''

class FreeListChainingFeat(Feat):
    '''The physical page allocator shall maintain an intrusive singly-linked list
    (freelist) where the first 8 bytes of each unallocated 4096-byte physical frame
    store the 64-bit address of the next free page frame.
    '''

class PageBoundaryValidationFeat(Feat):
    '''The deallocation routine (kfree) shall validate that the target address is
    page-aligned (pa % 4096 == 0), greater than or equal to `end`, and strictly
    less than `PHYSTOP` (0x88000000), halting via panic diagnostics on violation.
    '''

class PageScrubbingFeat(Feat):
    '''The allocator shall scrub page frames upon release or acquisition to detect
    dangling references and prevent information leakage, filling freed pages with
    junk bytes and zeroing freshly allocated pages.
    '''

class KallocAllocationFeat(Feat):
    '''The allocation routine (kalloc) shall pop the head frame from the free list,
    update the freelist pointer, and return the 64-bit frame address in register a0,
    or return 0 (NULL) when out of memory.
    '''

class KfreeDeallocationFeat(Feat):
    '''The deallocation routine (kfree) shall take a 4KB physical page address in
    register a0, scrub its contents, and prepend the frame onto the head of the free list.
    '''

class KinitRangeInitializationFeat(Feat):
    '''The allocator initialization routine (kinit) shall sweep the memory region
    between `end` and `PHYSTOP` in 4096-byte steps, invoking kfree on each page
    to construct the initial pool of available physical memory frames.
    '''

class AllocatorConcurrentSafetyFeat(Feat):
    '''The physical memory allocator state shall be protected against concurrent
    data races across multiple CPU harts using an atomic or spinlock synchronization barrier.
    '''
