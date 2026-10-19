'''
Declarative specification for the Machine Configuration Language (MCL)
'''

from .err import Feat, Req

class MachineConfigReq(Req):
    '''The operating system shall support a declarative Machine Configuration
    Language (MCL) that specifies hardware topology, physical memory boundaries,
    MMIO device ranges, and virtual memory mappings without imperative allocation loops.
    '''

class PermTypeFeat(Feat):
    '''The MCL shall define an algebraic data type for memory permissions (none,
    r, rw, rx, rwx) with decidable predicates for isReadable, isWritable, and isExecutable.
    '''

class MemoryMappingTypeFeat(Feat):
    '''The MCL shall define a structured memory mapping record containing
    symbolic name, virtual address, physical address, size, permissions,
    user/supervisor flag, and global TLB flag.
    '''

class MachineConfigTypeFeat(Feat):
    '''The MCL shall define a machine configuration record specifying the machine
    name, RAM base physical address, RAM size, and the list of memory mappings.
    '''

class Sv39PteEncodingFeat(Feat):
    '''The MCL compiler shall encode 64-bit Sv39 Page Table Entries (PTEs) with
    valid (V), read (R), write (W), execute (X), user (U), global (G), accessed (A),
    dirty (D), and 44-bit Physical Page Number (PPN) fields.
    '''

class Sv39TreeCompilerFeat(Feat):
    '''The MCL compiler shall deterministically compile a list of memory mappings
    into a complete 3-level Sv39 page table tree (Level 2 root, Level 1 intermediate,
    and Level 0 leaf pages).
    '''

class StaticPageTableAsmEmissionFeat(Feat):
    '''The MCL compiler shall emit the compiled Sv39 page table tree directly
    into 4096-byte aligned assembly data blocks (.align 12 with .quad words)
    so virtual memory can be activated without runtime heap allocation.
    '''

class SatpActivationFeat(Feat):
    '''The system shall provide instructions to activate Sv39 paging by loading
    satp with mode 8 and the root page table PPN, followed by sfence.vma to flush the TLB.
    '''

class WXSecurityProofFeat(Feat):
    '''The MCL shall provide automated compile-time proofs (via `decide`) that the
    declared memory mappings strictly enforce W-xor-X (no mapping is both writable and executable).
    '''

class KernelIsolationProofFeat(Feat):
    '''The MCL shall provide automated compile-time proofs (via `decide`) that no
    kernel code, kernel data, or MMIO device mapping grants user accessibility.
    '''

class PageAlignmentProofFeat(Feat):
    '''The MCL shall provide automated compile-time proofs (via `decide`) that all
    mapping virtual addresses, physical addresses, and sizes are 4096-byte page aligned.
    '''

class MegapageOptimizationFeat(Feat):
    '''The MCL tree compiler shall map large aligned memory regions (kernel text
    and physical RAM pool) using 2MB Level 1 megapages to reduce the boot page table
    memory footprint from 64 tables down to 7 tables.
    '''

class ImmediateOverflowHandlingFeat(Feat):
    '''The MCL assembly emission shall automatically detect page table entry offsets
    that exceed the RISC-V 12-bit signed immediate boundary (offset >= 2048) and emit
    temporary base register adjustments to avoid assembler overflow errors.
    '''

class ConcreteTableProofFeat(Feat):
    '''The MCL shall prove via compile-time reflection (rfl and decide) that the
    emitted static page table entries strictly enforce Read-Execute on text,
    Read-Write on RAM, and Read-Write on device MMIO registers.
    '''

class TrapVectorMappingFeat(Feat):
    '''The MCL machine configuration topology shall declare the supervisor trap
    vector symbol (trapVector := "kernelvec") and map its address space within
    the executable, read-only kernel text mapping.
    '''

