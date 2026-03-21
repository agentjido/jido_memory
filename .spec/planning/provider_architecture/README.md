# Canonical Memory Provider Architecture Plan

This planning set tracks the rollout of the canonical memory provider system in `jido_memory` and the downstream MemoryOS provider adoption in `jido_memory_os`.

## Phases
- `phase-01-provider-core-contract-and-basic-provider-backbone.md`
- `phase-02-capability-negotiation-and-provider-aware-runtime-facade.md`
- `phase-03-canonical-plugin-actions-and-compatibility-migration.md`
- `phase-04-memory-os-provider-adoption-and-advanced-capability-bridge.md`
- `phase-05-cross-repo-documentation-release-alignment-and-full-provider-validation.md`

## Delivery Rules
- `Jido.Memory.Runtime`, `recall/2`, `Jido.Memory.ETSPlugin`, and tuple-style public results stay compatible through the rollout.
- `Jido.Memory.Plugin` is the common provider-aware plugin for core memory flows.
- `Jido.MemoryOS.Plugin` remains the advanced plugin for MemoryOS-specific routes such as `pre_turn` and `post_turn`.
- Every phase ends with explicit integration coverage.
