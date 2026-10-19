# Carrying over to seL4

Origin repo: /usr/backup-working/work/seL4 (kernel C, ~10k lines in
src/kernel, src/object, src/api).

- tools/bitfield_gen.py and the 25 .bf files are a ready test suite and the
  model for the Layout stage.
- Syscall surface is described in XML (libsel4/include/api/syscall.xml,
  interfaces/object-api*.xml); the same single-description idea replaces the
  five places a syscall lives today (xml, stubs, decode, spec, proofs).
- AArch64 machine primitives (barriers, TLB ops, cache maintenance, sysreg
  access) are ~40 leaf functions in include/arch/arm/arch/64/mode/machine.h.
- seL4 is event-driven, run-to-completion, no kernel concurrency: much easier
  than xv6 on difficulties 1, 2, 6 in file 06. Hard parts are CDT/revoke,
  untyped retype, MCS scheduling, and the IPC fastpath (prove equal to slowpath).
- Do xv6 first; the layer technique and ISA-trust approach then transfer.
