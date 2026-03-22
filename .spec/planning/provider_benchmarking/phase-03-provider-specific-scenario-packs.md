# Phase 3 - Provider-Specific Scenario Packs

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Provider.Tiered`
- `Jido.Memory.Provider.Mirix`
- `Jido.Memory.LongTermStore.Postgres`
- Planned benchmark helper modules

## Relevant Assumptions / Defaults
- Provider-specific scenarios remain explicitly separate from the shared benchmark matrix.
- MIRIX ingestion and vault isolation remain provider-direct.
- Durable long-term comparisons stay opt-in.

[ ] 3 Phase 3 - Provider-Specific Scenario Packs
  Add advanced provider benchmark packs that evaluate richer behavior without redefining the shared benchmark contract.

  [ ] 3.1 Section - Tiered Lifecycle and Durable Storage Packs
    Evaluate Tiered-specific behavior that does not overlap with every provider.

    [ ] 3.1.1 Task - Add Tiered advanced benchmark scenarios
      Measure Tiered lifecycle and durable long-term behavior deliberately and separately.

      [ ] 3.1.1.1 Subtask - Add a lifecycle benchmark pack for promotion, consolidation, and explainability-rich retrieval.
      [ ] 3.1.1.2 Subtask - Add an opt-in durable-storage pack for Postgres-backed long-term comparisons.
      [ ] 3.1.1.3 Subtask - Keep Tiered advanced results labeled as provider-specific rather than shared-matrix regressions.

  [ ] 3.2 Section - MIRIX Ingestion and Protected Memory Packs
    Evaluate MIRIX-only advanced behavior in a way that respects the provider-direct boundary.

    [ ] 3.2.1 Task - Add MIRIX advanced benchmark scenarios
      Measure routed ingestion, retrieval planning, and vault isolation explicitly.

      [ ] 3.2.1.1 Subtask - Add a provider-direct ingestion benchmark pack for multimodal and batch routing summaries.
      [ ] 3.2.1.2 Subtask - Add a retrieval-planning benchmark pack for explanation richness and participating-memory-type selection.
      [ ] 3.2.1.3 Subtask - Add a protected-memory benchmark pack for vault isolation and exact-preservation boundaries.

  [ ] 3.3 Section - Provider-Specific Result Isolation
    Keep provider-specific output readable without conflating it with the shared benchmark matrix.

    [ ] 3.3.1 Task - Separate advanced pack reporting
      Make advanced results additive rather than redefining the common pass/fail signal.

      [ ] 3.3.1.1 Subtask - Store provider-specific benchmark outputs separately from shared benchmark results.
      [ ] 3.3.1.2 Subtask - Distinguish unsupported, skipped, and provider-direct-only scenarios explicitly.
      [ ] 3.3.1.3 Subtask - Keep provider-specific findings from automatically creating new common API obligations.

  [ ] 3.4 Section - Phase 3 Integration Tests
    Verify provider-specific packs run only where appropriate and remain isolated from the shared benchmark matrix.

    [ ] 3.4.1 Task - Provider-specific benchmark scenarios
      Confirm advanced packs respect the benchmark boundary.

      [ ] 3.4.1.1 Subtask - Verify Tiered advanced packs do not run against `:basic` or unsupported providers.
      [ ] 3.4.1.2 Subtask - Verify MIRIX ingestion and vault packs remain provider-direct and do not call shared runtime routes that do not exist.
      [ ] 3.4.1.3 Subtask - Verify shared benchmark summaries remain stable when provider-specific packs are skipped.
