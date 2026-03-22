# Phase 3 - Retrieval, Explainability, and Graph Augmentation

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Runtime`
- `Jido.Memory.Capability.ExplainableRetrieval`
- `Jido.Memory.Query`
- `Jido.Memory.Provider.Mem0`
- `Jido.Memory.ProviderContract`

## Relevant Assumptions / Defaults
- Canonical `retrieve/3` continues returning shared record lists.
- Explainability is the canonical lane for richer Mem0 retrieval context.
- Graph augmentation is optional and additive rather than a replacement for the base retrieval model.

[ ] 3 Phase 3 - Retrieval, Explainability, and Graph Augmentation
  Implement Mem0-style scoped retrieval, canonical explainability, and optional graph augmentation while preserving the shared record-oriented retrieve/3 result model.

  [x] 3.1 Section - Scoped Retrieval and Query Extension Baseline
    Add Mem0 retrieval behavior that respects scopes and provider-specific query hints without changing the base query contract.

    [x] 3.1.1 Task - Implement scoped retrieval behavior
      Make Mem0 retrieval useful for long-term memory access without requiring new shared query fields.

      [x] 3.1.1.1 Subtask - Support retrieval over scoped long-term memory using canonical query filters plus provider-native query extensions.
      [x] 3.1.1.2 Subtask - Add Mem0 query extension keys for scope control, retrieval mode, and graph augmentation hints.
      [x] 3.1.1.3 Subtask - Keep `recall/2` and `retrieve/3` aligned for the overlapping Mem0 query subset.

  [x] 3.2 Section - Explainability and Retrieval Traces
    Expose Mem0 retrieval context through the canonical explanation envelope rather than through a new shared result type.

    [x] 3.2.1 Task - Implement canonical Mem0 explainability output
      Make retrieval reasoning inspectable without widening the core facade.

      [x] 3.2.1.1 Subtask - Populate the canonical explanation envelope with provider metadata, query shape, result count, results, and Mem0-specific extensions.
      [x] 3.2.1.2 Subtask - Include scope context, retrieval strategy, and reconciliation-aware retrieval notes under `extensions.mem0`.
      [x] 3.2.1.3 Subtask - Keep explanation output structured enough for contract tests without overfitting the canonical envelope to Mem0 internals.

  [x] 3.3 Section - Optional Graph Augmentation
    Add entity and relationship augmentation as an additive retrieval enhancement rather than a replacement record model.

    [x] 3.3.1 Task - Implement graph augmentation behind the canonical retrieval boundary
      Make graph-aware retrieval available without redefining shared memory records.

      [x] 3.3.1.1 Subtask - Support optional graph augmentation through provider config and Mem0 query extensions.
      [x] 3.3.1.2 Subtask - Return graph-specific context through `extensions.mem0` or provider-direct helpers instead of replacing `retrieve/3` results.
      [x] 3.3.1.3 Subtask - Keep graph augmentation off by default and additive to the base retrieval path.

  [ ] 3.4 Section - Phase 3 Integration Tests
    Validate scoped retrieval, explainability, and optional graph augmentation while preserving the canonical retrieve/3 result shape.

    [ ] 3.4.1 Task - Scoped retrieval and explainability scenarios
      Verify Mem0 retrieval works through the shared runtime boundary.

      [ ] 3.4.1.1 Subtask - Verify Mem0 retrieves scoped canonical records through `Runtime.retrieve/3`.
      [ ] 3.4.1.2 Subtask - Verify `Runtime.explain_retrieval/3` returns the canonical envelope with Mem0-specific additive context.
      [ ] 3.4.1.3 Subtask - Verify Mem0 query extensions influence retrieval behavior without changing `Jido.Memory.Query` semantics for other providers.

    [ ] 3.4.2 Task - Graph augmentation scenarios
      Verify graph-style augmentation remains additive and optional.

      [ ] 3.4.2.1 Subtask - Verify graph augmentation enriches explanation output without replacing canonical record results.
      [ ] 3.4.2.2 Subtask - Verify graph augmentation can be disabled cleanly.
      [ ] 3.4.2.3 Subtask - Verify non-Mem0 providers remain unaffected by Mem0 graph-related query extensions and tests.
