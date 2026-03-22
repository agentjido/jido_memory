# Mem0 Provider Boundary

This subject records the draft direction for a Mem0-style provider inside the
canonical `jido_memory` architecture.

## Intent

Capture the repository-level contract for the built-in extraction-and-reconciliation
provider that emphasizes scoped long-term memory, incremental updates, optional
graph augmentation, and provider-direct maintenance workflows without widening
the canonical core.

```spec-meta
id: jido_memory.provider_mem0
kind: architecture
status: draft
summary: Draft boundary for the built-in Mem0 provider in jido_memory, covering extraction-and-reconciliation memory, scoped retrieval, and optional graph augmentation.
surface:
  - .spec/specs/provider_architecture.spec.md
  - .spec/specs/provider_capabilities.spec.md
  - .spec/specs/provider_facade.spec.md
  - .spec/specs/matrix/provider_surface_matrix.spec.md
  - .spec/specs/matrix/ingestion_matrix.spec.md
  - .spec/specs/matrix/retrieval_matrix.spec.md
  - lib/jido_memory/provider/mem0.ex
  - test/jido_memory/mem0_phase_01_integration_test.exs
  - test/jido_memory/mem0_phase_03_integration_test.exs
  - test/jido_memory/mem0_phase_04_integration_test.exs
```

## Requirements

```spec-requirements
- id: jido_memory.provider_mem0.extraction_reconciliation_boundary
  statement: A Mem0-style provider shall model long-term memory as extracted and reconciled salient facts rather than as raw transcript chunk storage, while still satisfying the canonical provider core contract.
  priority: must
  stability: evolving
- id: jido_memory.provider_mem0.scoped_memory_identity
  statement: A Mem0-style provider shall support scoped memory identities such as user, agent, app, or run context through provider configuration, metadata, or provider-native controls without changing the canonical provider selection model.
  priority: must
  stability: evolving
- id: jido_memory.provider_mem0.graph_augmentation_boundary
  statement: Optional graph-style memory augmentation for entity and relationship retrieval shall remain additive to the canonical retrieve/3 and explain_retrieval/3 surfaces rather than replacing the shared record-oriented result model.
  priority: must
  stability: evolving
- id: jido_memory.provider_mem0.provider_direct_advanced_ops
  statement: Advanced Mem0-style controls such as feedback, export, history, or provider-owned update semantics shall remain provider-direct until they demonstrate a reusable cross-provider canonical shape.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: jido_memory.provider_mem0.shared_facade_path
  given:
    - a plugin configuration that selects the built-in Mem0 provider
  when:
    - agent memory calls use the common plugin and runtime surface
  then:
    - canonical remember, retrieve, recall, and explainability flows remain stable while provider-native extraction and reconciliation stay behind the provider boundary
  covers:
    - jido_memory.provider_mem0.extraction_reconciliation_boundary
    - jido_memory.provider_mem0.provider_direct_advanced_ops
- id: jido_memory.provider_mem0.scoped_identity_path
  given:
    - a Mem0-style provider that maintains separate user, agent, app, or run memory scopes
  when:
    - the provider is configured through the canonical memory layer
  then:
    - the scoped identity model is expressed through provider configuration, metadata, or provider-native controls without changing shared provider selection precedence
  covers:
    - jido_memory.provider_mem0.scoped_memory_identity
- id: jido_memory.provider_mem0.graph_augmented_retrieval_path
  given:
    - a Mem0-style provider that augments retrieval with entity and relationship context
  when:
    - a caller asks for retrieval results or retrieval explanation through the canonical runtime
  then:
    - canonical record results remain stable while graph-specific context is exposed additively through explanation output or provider-direct APIs
  covers:
    - jido_memory.provider_mem0.graph_augmentation_boundary
    - jido_memory.provider_mem0.provider_direct_advanced_ops
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_memory/provider/mem0.ex
  covers:
    - jido_memory.provider_mem0.extraction_reconciliation_boundary
    - jido_memory.provider_mem0.scoped_memory_identity
    - jido_memory.provider_mem0.graph_augmentation_boundary
    - jido_memory.provider_mem0.provider_direct_advanced_ops
- kind: source_file
  target: test/jido_memory/mem0_phase_03_integration_test.exs
  covers:
    - jido_memory.provider_mem0.graph_augmentation_boundary
- kind: source_file
  target: test/jido_memory/mem0_phase_04_integration_test.exs
  covers:
    - jido_memory.provider_mem0.provider_direct_advanced_ops
```

<!-- covers: jido_memory.provider_mem0.extraction_reconciliation_boundary -->
<!-- covers: jido_memory.provider_mem0.scoped_memory_identity -->
<!-- covers: jido_memory.provider_mem0.graph_augmentation_boundary -->
<!-- covers: jido_memory.provider_mem0.provider_direct_advanced_ops -->
