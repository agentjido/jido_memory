# Phase 2 - Extraction, Reconciliation, and Memory Maintenance

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Provider.Mem0`
- `Jido.Memory.Capability.Ingestion`
- `Jido.Memory.Runtime`
- `Jido.Memory.Query`
- `Jido.Memory.Record`

## Relevant Assumptions / Defaults
- Canonical `remember/3` remains available for direct structured writes.
- Mem0-style extraction and reconciliation are additive and do not replace the shared write contract.
- Memory-maintenance operations stay provider-direct unless they later prove reusable across providers.

[ ] 2 Phase 2 - Extraction, Reconciliation, and Memory Maintenance
  Implement the Mem0-style extraction pipeline, reconciliation logic, and maintenance semantics that distinguish this provider from raw transcript or raw chunk storage.

  [x] 2.1 Section - Extraction Pipeline and Candidate Memory Generation
    Add the ingestion path that extracts salient memories from interaction inputs while preserving the canonical write path for direct record writes.
    Completed by adding provider-direct Mem0 ingestion, deterministic candidate extraction from message and entry payloads, stable ingestion summaries, and extraction-context metadata in provider info.

    [x] 2.1.1 Task - Implement Mem0 extraction ingestion
      Introduce provider-defined extraction that converts interaction inputs into candidate memory facts.

      [x] 2.1.1.1 Subtask - Implement `Jido.Memory.Capability.Ingestion` on the Mem0 provider.
      [x] 2.1.1.2 Subtask - Accept conversational or interaction-oriented payloads that can generate candidate memories from message pairs or interaction batches.
      [x] 2.1.1.3 Subtask - Return deterministic ingestion summaries describing extracted candidates, skipped candidates, and created or updated memory ids.

    [x] 2.1.2 Task - Add summary and recency context handling
      Support the contextual inputs Mem0-style extraction needs without widening the shared plugin or runtime facade.

      [x] 2.1.2.1 Subtask - Define provider config for recent-message windows and optional conversation-summary context.
      [x] 2.1.2.2 Subtask - Keep summary generation provider-owned rather than a new shared runtime responsibility.
      [x] 2.1.2.3 Subtask - Surface extraction-context settings through `info/2` and provider metadata.

  [x] 2.2 Section - Reconciliation and Update Semantics
    Implement the ADD, UPDATE, DELETE, and NOOP-style maintenance flow that reconciles candidate memories against existing stored memory.
    Completed by adding provider-owned similarity lookup, deterministic add/update/delete/noop reconciliation outcomes, maintenance summaries in ingestion results, and additive provenance in Mem0 record metadata.

    [x] 2.2.1 Task - Add reconciliation decision flow
      Make the Mem0 provider maintain long-term memory coherence rather than appending every extracted fact blindly.

      [x] 2.2.1.1 Subtask - Retrieve semantically similar existing memories before committing each candidate memory.
      [x] 2.2.1.2 Subtask - Implement provider-owned reconciliation outcomes equivalent to add, update, delete, and no-op semantics.
      [x] 2.2.1.3 Subtask - Preserve reconciliation provenance in provider metadata or provider-direct history rather than changing the canonical record schema.

    [x] 2.2.2 Task - Keep maintenance semantics provider-direct
      Preserve the additive extension boundary while exposing enough insight for tooling and tests.

      [x] 2.2.2.1 Subtask - Keep reconciliation controls provider-direct in v1 rather than adding new shared runtime APIs.
      [x] 2.2.2.2 Subtask - Expose maintenance summaries through ingestion results, explainability output, `info/2`, or provider-direct inspection helpers.
      [x] 2.2.2.3 Subtask - Keep unsupported-maintenance behavior deterministic for other providers.

  [x] 2.3 Section - Canonical Write Compatibility Hardening
    Preserve direct structured writes and compatibility callers while the richer Mem0 maintenance path is added.
    Completed by keeping direct `remember/3` on the shared write path, tagging direct and ingestion-driven writes distinctly in Mem0 metadata, and verifying plugin auto-capture still routes through canonical writes.

    [x] 2.3.1 Task - Maintain direct canonical write behavior
      Prevent extraction and reconciliation from making the shared write surface harder to use.

      [x] 2.3.1.1 Subtask - Keep `remember/3` valid for direct, explicit record writes without requiring extraction payloads.
      [x] 2.3.1.2 Subtask - Distinguish direct canonical writes from extraction-driven writes in provider metadata and test fixtures.
      [x] 2.3.1.3 Subtask - Keep plugin auto-capture on the shared `remember/3` path unless explicit Mem0 ingestion is deliberately opted into later.

  [ ] 2.4 Section - Phase 2 Integration Tests
    Validate extraction, reconciliation, and maintenance flows while preserving the canonical write boundary.

    [ ] 2.4.1 Task - Extraction and maintenance scenarios
      Verify the Mem0 provider can ingest interaction inputs and reconcile them coherently.

      [ ] 2.4.1.1 Subtask - Verify Mem0 ingestion extracts candidate memories and returns deterministic maintenance summaries.
      [ ] 2.4.1.2 Subtask - Verify reconciliation can add, update, delete, or skip candidate memories without corrupting scoped memory state.
      [ ] 2.4.1.3 Subtask - Verify reconciliation provenance stays additive and does not leak into the shared record contract unexpectedly.

    [ ] 2.4.2 Task - Canonical write compatibility scenarios
      Verify direct shared writes remain stable while Mem0 maintenance behavior grows richer.

      [ ] 2.4.2.1 Subtask - Verify `remember/3` still works for direct structured writes through Mem0.
      [ ] 2.4.2.2 Subtask - Verify shared plugin auto-capture remains on the canonical write path.
      [ ] 2.4.2.3 Subtask - Verify existing non-Mem0 providers remain unaffected by the new maintenance machinery.
