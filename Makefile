TOOLPREFIX = riscv64-unknown-elf-
CC = $(TOOLPREFIX)gcc
LD = $(TOOLPREFIX)ld
OBJDUMP = $(TOOLPREFIX)objdump
GDB = $(TOOLPREFIX)gdb
QEMU = qemu-system-riscv64

CFLAGS = -Wall -Werror -O -fno-omit-frame-pointer -ggdb -gdwarf-2 -march=rv64gc -mcmodel=medany -ffreestanding -nostdlib -fno-common
LDFLAGS = -z max-page-size=4096
QEMUOPTS = -machine virt -bios none -kernel build/kernel.elf -m 128M -smp 1 -nographic

.PHONY: all qemu qemu-verbose qemu-trace qemu-gdb gdb disasm clean FORCE

all: build/kernel.elf build/kernel.asm build/kernel.sym

build/boot.S: FORCE
	lake build
	lake exe lean-xv6

FORCE:

build/boot.o: build/boot.S
	$(CC) $(CFLAGS) -c build/boot.S -o build/boot.o

build/kernel.elf: build/boot.o kernel.ld
	$(LD) $(LDFLAGS) -T kernel.ld -o build/kernel.elf build/boot.o

build/kernel.asm: build/kernel.elf
	$(OBJDUMP) -S build/kernel.elf > build/kernel.asm

build/kernel.sym: build/kernel.elf
	$(OBJDUMP) -t build/kernel.elf | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > build/kernel.sym

# 1. Normal run
qemu: build/kernel.elf
	$(QEMU) $(QEMUOPTS)

# 2. Verbose run: logs executed instructions, interrupts, and traps to build/qemu.log
qemu-verbose: build/kernel.elf
	@echo "Starting QEMU with instruction trace logged to build/qemu.log..."
	$(QEMU) $(QEMUOPTS) -d in_asm,int,guest_errors -D build/qemu.log
	@echo "QEMU log written to build/qemu.log (first 40 lines):"
	@head -n 40 build/qemu.log

# 3. Live trace run: streams instruction execution and trap transitions directly to stderr
qemu-trace: build/kernel.elf
	$(QEMU) $(QEMUOPTS) -d in_asm,int,guest_errors

# 4. GDB debug: starts QEMU frozen at 0x80000000 waiting for GDB on port 1234
qemu-gdb: build/kernel.elf
	@echo "*** Now run 'make gdb' in another terminal to attach ***"
	$(QEMU) $(QEMUOPTS) -s -S

# 5. Connect GDB client
gdb: build/kernel.elf
	$(GDB) -ex "file build/kernel.elf" -ex "target remote :1234" -ex "break _entry" -ex "continue"

disasm: build/kernel.asm
	cat build/kernel.asm

clean:
	rm -rf build
