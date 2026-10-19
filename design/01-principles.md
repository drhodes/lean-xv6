# Principles

## Thin interfaces make proofs cheap
Cost of a refinement proof at a boundary ~ (operations exposed) x (state and
invariants visible through the interface).
- Fewer operations: fewer simulation lemmas.
- Less visible state: simpler coupling relation, fewer frame lemmas.
- Invariants stay local: a layer owns and proves its invariants once; layers
  above see only the contract. (l4v pays the full n x m product because its
  invariants are global.)
- Small semantic gaps per layer are mostly automatable (simp, omega, bv_decide).
- Changing an implementation behind an unchanged interface re-proves nothing above.

## Two different things, do not conflate
- Compilation stages: a few languages, each lowering proved once, generic.
- Abstraction layers: many abstract machines, each with a tiny API implemented
  only on the layer below. The kernel-specific proofs live here.
Precedent: CertiKOS certified abstraction layers; Hyperkernel finite interfaces.

## Counting rule
Add a layer when the kind of value or the kind of control flow changes, or when
an interface can be made meaningfully narrower. Do not split by subsystem name
alone. Cost of a layer is low only if its interface is genuinely thin.

## Catch
Designing thin interfaces is the hard part. Operations that cut across layers
(exit/wait touching procs, memory and files; exec; pipes with sleep/wakeup)
must be factored so they do not punch through. Performance-sensitive paths may
need to be proved equivalent to a slow reference path instead.

## Trust as definitions, not axioms
The ISA model is ordinary Lean definitions, not `axiom`. Inconsistent axioms
make every theorem vacuous; a wrong definition is merely testable. Differential
test the model against Sail/Spike/QEMU.
