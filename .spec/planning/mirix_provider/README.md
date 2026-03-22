# MIRIX Provider Plan

This planning set tracks the additive core changes and built-in MIRIX provider rollout in `jido_memory`.

## Phases
- `phase-01-additive-core-capability-and-query-extension-baseline.md`
- `phase-02-selective-runtime-facade-and-provider-direct-boundary.md`
- `phase-03-mirix-built-in-provider-memory-type-substrate.md`
- `phase-04-mirix-active-retrieval-ingestion-and-protected-memory.md`
- `phase-05-mirix-adoption-docs-and-release-gated-acceptance.md`

## Current Status
- Phase 1 is implemented on the current branch.
- Phase 2 is implemented on the current branch.
- Phase 3 is implemented on the current branch.
- Phase 4 is implemented on the current branch.
- Phase 5 is pending.

## Delivery Rules
- `Jido.Memory.Provider` stays small and cross-provider.
- `Jido.Memory.Runtime` and `Jido.Memory.Plugin` remain selective and core-oriented.
- MIRIX-specific ingestion and protected-memory workflows stay provider-direct in v1.
- Every phase ends with explicit integration coverage.
