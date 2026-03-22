# Phase 2 - Selective Runtime Facade and Provider-Direct Boundary

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Runtime`
- `Jido.Memory.Plugin`
- `Jido.Memory.Actions.Retrieve`
- `Jido.Memory.Actions.Remember`
- `Jido.Memory.Capability.ExplainableRetrieval`
- `Jido.Memory.ProviderContract`

## Relevant Assumptions / Defaults
- The shared runtime remains selective in v1.
- No common `Runtime.ingest/3`, no common ingest action, and no shared vault action land in this phase.
- MIRIX-specific advanced flows will be provider-direct but still capability-discoverable.

[ ] 2 Phase 2 - Selective Runtime Facade and Provider-Direct Boundary
  Align the shared runtime and plugin surfaces with the new ADR so MIRIX can be rich without making the core facade MIRIX-shaped.

  [ ] 2.1 Section - Runtime Retrieval and Explainability Boundary Hardening
    Preserve canonical retrieval semantics while making explainability rich enough for MIRIX routing and planning traces.

    [ ] 2.1.1 Task - Standardize the canonical explanation envelope
      Make all explainable providers return one stable top-level explanation shape with provider-specific detail under extensions.

      [ ] 2.1.1.1 Subtask - Define the canonical top-level explanation keys as `provider`, `namespace`, `query`, `result_count`, `results`, and `extensions`.
      [ ] 2.1.1.2 Subtask - Keep Tiered explanation output aligned by moving all tier-specific details under `extensions.tiered`.
      [ ] 2.1.1.3 Subtask - Reserve `extensions.mirix` for memory-type participation, retrieval plans, routing traces, and ranking context.

    [ ] 2.1.2 Task - Preserve the selective runtime boundary
      Keep shared runtime helpers limited to broadly reusable operations.

      [ ] 2.1.2.1 Subtask - Keep `Runtime.retrieve/3`, `Runtime.explain_retrieval/3`, `Runtime.capabilities/2`, and `Runtime.info/3` as the only MIRIX-relevant shared read-side helpers.
      [ ] 2.1.2.2 Subtask - Do not add `Runtime.ingest/3`, `Runtime.vault_*`, or provider-manager control wrappers in v1.
      [ ] 2.1.2.3 Subtask - Keep unsupported advanced operations normalized to `{:error, {:unsupported_capability, capability}}` when invoked through shared runtime helpers.

  [ ] 2.2 Section - Common Plugin and Action Boundary Hardening
    Keep the agent-facing plugin and actions stable while allowing provider-native retrieval extensions through existing shared routes.

    [ ] 2.2.1 Task - Add extension-aware retrieval inputs without widening the plugin surface
      Let callers reach MIRIX retrieval features from the common read path without turning the plugin into a specialized memory control plane.

      [ ] 2.2.1.1 Subtask - Add `query_extensions` to `Jido.Memory.Actions.Retrieve` and `Recall`, normalized into `Query.extensions`.
      [ ] 2.2.1.2 Subtask - Keep `Remember` limited to canonical record attrs and provider-agnostic compatibility fields.
      [ ] 2.2.1.3 Subtask - Preserve `Jido.Memory.Plugin` as core-memory only with no new signal routes for ingest or vault operations.

    [ ] 2.2.2 Task - Clarify provider-direct advanced entrypoints
      Make provider-native operations discoverable without pretending they are common plugin/runtime features.

      [ ] 2.2.2.1 Subtask - Document and test that advanced MIRIX ingestion and vault workflows are invoked directly on `Jido.Memory.Provider.Mirix`.
      [ ] 2.2.2.2 Subtask - Keep plugin checkpoint and restore behavior provider-agnostic with no MIRIX-specific state payloads.
      [ ] 2.2.2.3 Subtask - Preserve auto-capture through canonical `remember/3` only; MIRIX advanced ingestion is opt-in and explicit.

  [ ] 2.3 Section - Contract Helpers and Provider-Direct Discovery
    Extend helper surfaces so built-in and external provider tests can reason about the new additive lanes.

    [ ] 2.3.1 Task - Expand provider contract helper coverage
      Make the provider contract tooling aware of the new extension lanes without adding new required callbacks.

      [ ] 2.3.1.1 Subtask - Extend `ProviderContract.supports?/2` usage in tests to cover ingestion and governance capability keys.
      [ ] 2.3.1.2 Subtask - Add provider contract helper expectations for canonical explanation envelope shape.
      [ ] 2.3.1.3 Subtask - Keep provider-direct APIs out of the required contract suite and cover them in provider-specific tests instead.

  [ ] 2.4 Section - Phase 2 Integration Tests
    Validate that the shared facade remains narrow and stable while provider-native lanes become discoverable.
