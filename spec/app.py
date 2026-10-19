'''
Specifications for the lean-xv6 Application Boot, Build System, and Linker Layout
'''

from .err import Feat, Req

class Xv6BootReq(Req):
    '''The system shall provide a verified boot sequence (_entry and start)
    that initializes per-hart stacks in Machine mode, configures PMP and trap
    delegation, and drops privilege to Supervisor mode via mret to execute main.
    '''

class BuildMechanismReq(Req):
    '''The build mechanism shall provide a Makefile orchestrating Lean 4 code
    generation (Lake), assembly emission, linking with kernel.ld into a bootable
    ELF, and reproducible QEMU execution targets.
    '''

class MedanyLinkerLayoutFeat(Feat):
    '''The linker script (kernel.ld) shall position the kernel entry point at 0x80000000,
    enforce medium-any addressing (-mcmodel=medany), align page table sections to 4096
    bytes, and define boundary symbols (etext, _trampoline, end).
    '''

class QemuVerboseBootFeat(Feat):
    '''The build system shall provide verbose QEMU boot targets (e.g. `make qemu-verbose`
    and `make qemu-trace`) that log instruction execution, hardware interrupts,
    trap transitions, and guest errors to aid low-level debugging.
    '''

class QemuGdbDebugFeat(Feat):
    '''The build system shall provide GDB targets (`make qemu-gdb` and `make gdb`)
    enabling instruction-level and register-level debugging of the boot sequence
    over GDB remote protocol on port 1234.
    '''

class AutomatedCleanExitFeat(Feat):
    '''The kernel boot test sequence shall write to the QEMU test finisher device
    upon completing verification, cleanly terminating QEMU with exit code 0 to
    enable non-interactive automated testing in CI.
    '''

class BootDagParallelInitFeat(Feat):
    '''The boot sequence shall decompose initialization tasks according to a
    directed acyclic dependency graph into three orthogonal domains (Traps/Interrupts,
    Memory/Processes, Storage/Tables) that synchronize at an atomic barrier before
    userinit, enabling multicore parallel boot and compile-time pre-initialization.
    '''

class KernelTextDataSeparationFeat(Feat):
    '''The linker script (kernel.ld) shall align the boundary between the executable
    kernel code (.text) and writable data sections (.rodata, .data, .bss) to a 2MB
    Level 1 megapage boundary (0x80200000), physically separating code from data to
    strictly enforce compile-time W-xor-X protection across the address space.
    '''

