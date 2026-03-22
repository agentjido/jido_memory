# Phase 4 - MIRIX Active Retrieval, Ingestion, and Protected Memory

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Provider.Mirix`
- `Jido.Memory.Capability.Ingestion`
- `Jido.Memory.Capability.ExplainableRetrieval`
- `Jido.Memory.Capability.Governance`
- `Jido.Memory.Query`
- `Jido.Memory.Runtime`

## Relevant Assumptions / Defaults
- MIRIX active retrieval is exposed through canonical `retrieve/3` and `explain_retrieval/3`.
- MIRIX advanced ingestion and vault workflows remain provider-direct in v1.
- Protected memory is explicit-only and never piggybacks on canonical `retrieve/3`.

[ ] 4 Phase 4 - MIRIX Active Retrieval, Ingestion, and Protected Memory
  Implement the MIRIX-specific advanced behaviors that motivated the new core seams while preserving the additive extension boundary.

  [ ] 4.1 Section - Active Retrieval Planning and Explainability Traces
    Implement MIRIX’s routed retrieval behavior and expose its planning traces through the canonical explainability boundary.

  [ ] 4.2 Section - Provider-Direct Multimodal and Batch Ingestion
    Implement the new ingestion capability for MIRIX without widening the shared runtime or plugin surfaces.

  [ ] 4.3 Section - Protected Memory Governance and Vault Workflows
    Implement MIRIX’s knowledge-vault behavior as explicit protected-memory APIs rather than common core behavior.

  [ ] 4.4 Section - Phase 4 Integration Tests
    Validate MIRIX’s advanced behaviors while preserving the canonical runtime and plugin boundaries.
