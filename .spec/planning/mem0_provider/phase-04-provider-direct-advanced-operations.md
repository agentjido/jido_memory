# Phase 4 - Provider-Direct Advanced Operations

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Provider.Mem0`
- `Jido.Memory.Capability.Ingestion`
- `Jido.Memory.Capability.Governance`
- `Jido.Memory.Runtime`
- `Jido.Memory.Plugin`

## Relevant Assumptions / Defaults
- Feedback, export, history, and provider-owned maintenance controls remain provider-direct in v1.
- The shared runtime and plugin surfaces stay unchanged unless a cross-provider pattern becomes obvious.
- Phase 4 is where Mem0-specific operational affordances become explicit.

[x] 4 Phase 4 - Provider-Direct Advanced Operations
  Implement the Mem0-specific operational APIs that are valuable for this provider but not yet justified as common runtime or plugin features.
  Completed by adding provider-direct feedback, history, export, and maintenance operations; surfacing those boundaries through Mem0 provider metadata; and finishing dedicated integration coverage that keeps the shared runtime and plugin surfaces selective.

  [x] 4.1 Section - Feedback and History APIs
    Add provider-direct feedback and history surfaces that support Mem0-style memory maintenance and inspection.
    Completed by adding scoped provider-direct feedback updates, a dedicated Mem0 history API, and internal event logging for direct writes, reconciliation outcomes, and feedback actions.

    [x] 4.1.1 Task - Add feedback and history operations
      Make Mem0 advanced inspection and curation possible without widening the shared facade.

      [x] 4.1.1.1 Subtask - Add provider-direct feedback APIs for marking memories or maintenance outcomes as useful or not useful.
      [x] 4.1.1.2 Subtask - Add provider-direct history APIs for inspecting reconciliation events and memory evolution.
      [x] 4.1.1.3 Subtask - Keep feedback and history semantics out of the shared runtime until another provider demonstrates the same shape.

  [x] 4.2 Section - Export and Maintenance Controls
    Add provider-direct export and maintenance controls for Mem0-specific operational workflows.
    Completed by adding scoped export snapshots, maintenance-summary refresh, an explicit reconciliation rerun helper, and structured advanced-operation metadata in provider info.

    [x] 4.2.1 Task - Add export and maintenance operations
      Support operational workflows around Mem0 memory state without forcing those concerns into the canonical provider contract.

      [x] 4.2.1.1 Subtask - Add provider-direct export APIs for scoped memory snapshots or maintenance summaries.
      [x] 4.2.1.2 Subtask - Add provider-direct maintenance helpers for summary refresh, reconciliation re-runs, or cleanup workflows.
      [x] 4.2.1.3 Subtask - Surface available advanced operations through structured capability or info metadata.

  [x] 4.3 Section - Runtime and Plugin Boundary Hardening
    Reconfirm that Mem0 advanced operations stay additive and do not leak onto the common plugin or runtime path accidentally.
    Completed by making the boundary explicit in Mem0 provider info metadata so callers can discover shared-vs-provider-direct operations without adding new common runtime helpers or plugin routes.

    [x] 4.3.1 Task - Keep the common surface selective
      Preserve the current architectural boundary even as Mem0 grows richer.

      [x] 4.3.1.1 Subtask - Avoid adding shared runtime wrappers for Mem0 feedback, export, or history in v1.
      [x] 4.3.1.2 Subtask - Keep shared plugin signal routes limited to core memory operations.
      [x] 4.3.1.3 Subtask - Keep capability discovery and provider info rich enough that advanced Mem0 operations remain discoverable without becoming canonical.

  [x] 4.4 Section - Phase 4 Integration Tests
    Validate provider-direct advanced operations while preserving the shared runtime and plugin boundaries.
    Completed by adding Mem0 Phase 4 integration coverage for scoped feedback and history, export and maintenance controls, shared-boundary checks, and regression coverage for non-Mem0 providers.

    [x] 4.4.1 Task - Provider-direct advanced-operation scenarios
      Verify Mem0 advanced operations work and stay explicitly provider-owned.

      [x] 4.4.1.1 Subtask - Verify feedback and history APIs behave deterministically for scoped memory data.
      [x] 4.4.1.2 Subtask - Verify export and maintenance APIs work without introducing new shared runtime routes.
      [x] 4.4.1.3 Subtask - Verify advanced-operation metadata is discoverable through capabilities or `info/2`.

    [x] 4.4.2 Task - Shared boundary scenarios
      Verify the common runtime and plugin surfaces stay selective.

      [x] 4.4.2.1 Subtask - Verify no common plugin routes exist for Mem0-specific feedback, export, or history workflows.
      [x] 4.4.2.2 Subtask - Verify no new shared runtime helpers leak in for Mem0-only advanced operations.
      [x] 4.4.2.3 Subtask - Verify existing built-in and external-provider paths remain unaffected.
