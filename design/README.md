# lean-xv6 design notes

Goal: a verified xv6 (RISC-V) built as a stack of small Lean 4 languages and
thin abstraction layers, compiled down to RISC-V machine code. Trust is drawn
at the ISA: the RISC-V model (plus device models) is the only axiom-like base.

Origin: discussion started from "port seL4 to Lean 4". seL4 is the long-term
target; xv6 is the first target because it is small, already layered, and has
a free test oracle (usertests).

Files
- 01-principles.md    thin interfaces, layers vs compilation stages
- 02-trust-boundary.md  what the ISA model must contain
- 03-language-stack.md  the compilation stages
- 04-abstraction-layers.md  the xv6 layer table and its interfaces
- 05-primitives-and-syscalls.md  Prim declarations, syscall interface DSL
- 06-xv6-difficulties.md  concurrency, blocking, crash safety, missing spec
- 07-roadmap.md  build order and open questions
- 08-sel4-notes.md  what carries over to seL4 later
- 09-machine-configuration-language.md  declarative machine topology and compile-time Sv39 page tables
- 10-boot-dag-and-parallel-initialization.md  boot dependency graph, orthogonal domains, and multicore boot pipeline
