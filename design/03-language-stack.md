# Compilation stages (few, generic proofs)

Because the ISA is the trust line, the compiler is inside the proof: either
verify the backend or translation-validate each output. Preference: our own
backend from Low IR straight to RISC-V encodings (Bedrock2 style). xv6 is small
enough that naive codegen is acceptable. LLVM is not used (unverified, messy
undef/poison semantics, would require validating every binary).

| Stage | Values | Control | Notes |
|-------|--------|---------|-------|
| K  Kernel DSL | typed objects, lists, maps | structured, monadic, total or bounded | where the kernel is written and abstract-layer proofs live |
| L  Layout | structs, bitfields in a typed heap | structured, typed pointers | replaces C struct layout; port of the seL4 bitfield_gen idea |
| W  Low IR | machine words, byte memory | structured imperative, calls, bounded stack | Bedrock2/Cminor-like |
| R  RISC-V | instruction words | the ISA | emitted directly; semantics = ISA model |

Notes
- No separate SSA/CFG stage initially; Low IR compiled to RISC-V by a simple
  stack-slot register allocator. Optimisation is not a goal.
- Inline asm (trap vectors, swtch, context save/restore) is a small asm DSL
  whose semantics are ISA-level, linked into W as Prim leaves (see 05).
- Each pass: either proof for all programs, or a validator that checks one run
  and produces a certificate. Mixing is fine; swap later.
- Kernel DSL features: sleep/yield as explicit suspension points, interrupt
  enable/disable as explicit effects, no dynamic allocation outside kalloc.
