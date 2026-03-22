# Mem0 Provider Plan

This planning set tracks the implementation of a Mem0-style provider in `jido_memory`.

## Summary
- Implement a Mem0-style provider as an extraction-and-reconciliation memory path that still satisfies the canonical `Jido.Memory.Provider` contract.
- Preserve the shared plugin and runtime surface while keeping Mem0-specific memory maintenance, scoped identity controls, and optional graph augmentation additive.
- Add provider-direct advanced operations only where the common facade does not yet have a reusable cross-provider shape.

## Phases
- `phase-01-mem0-provider-baseline-and-scoped-identity.md`
- `phase-02-extraction-reconciliation-and-memory-maintenance.md`
- `phase-03-retrieval-explainability-and-graph-augmentation.md`
- `phase-04-provider-direct-advanced-operations.md`
- `phase-05-adoption-docs-and-release-gated-acceptance.md`

## Current Status
- Phase 1 is complete.
- Phase 2 is complete.
- Phase 3 is complete.
- Phase 4 is complete.
- Phase 5 is complete.

## Delivery Rules
- `Jido.Memory.Provider` stays small and cross-provider.
- `Jido.Memory.Runtime` and `Jido.Memory.Plugin` remain selective and core-oriented.
- Mem0-specific extraction, reconciliation, feedback, export, history, and optional graph controls stay additive through capabilities, explainability output, or provider-direct APIs.
- Every phase ends with explicit integration coverage.
