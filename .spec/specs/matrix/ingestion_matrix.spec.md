# Ingestion Matrix

This subject defines how canonical writes and richer ingestion flows coexist in
the provider architecture.

## Intent

Preserve the stable core write path while allowing providers to negotiate batch,
multimodal, or routed ingestion capabilities additively.

```spec-meta
id: jido_memory.matrix.ingestion
kind: architecture
status: draft
summary: Draft matrix for core writes versus optional ingestion capabilities in pluggable memory providers.
surface:
  - .spec/decisions/0001-additive-provider-extension-boundary.md
  - lib/jido_memory/provider.ex
  - lib/jido_memory/plugin.ex
  - lib/jido_memory/actions/*.ex
decisions:
  - jido_memory.provider_extension_boundary
```

## Requirements

```spec-requirements
- id: jido_memory.matrix.ingestion.core_write_stability
  statement: The canonical remember/3 path shall remain the shared minimal write operation for structured memory attrs even as richer providers add more advanced ingestion flows.
  priority: must
  stability: evolving
- id: jido_memory.matrix.ingestion.optional_ingestion_lane
  statement: Batch, multimodal, or routed ingestion flows shall enter through an optional ingestion capability family or provider-direct APIs rather than by changing the required core write contract.
  priority: must
  stability: evolving
- id: jido_memory.matrix.ingestion.plugin_core_only_boundary
  statement: The common memory plugin shall remain core-memory oriented and shall not require every provider to expose advanced ingestion routes through the shared agent-facing plugin surface.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: jido_memory.matrix.ingestion.basic_write_path
  given:
    - a provider that supports only the canonical memory write path
  when:
    - an application writes structured memory attrs
  then:
    - the provider succeeds through remember/3 without needing any ingestion-specific API surface
  covers:
    - jido_memory.matrix.ingestion.core_write_stability
- id: jido_memory.matrix.ingestion.multimodal_provider_path
  given:
    - a provider such as Mirix that accepts batches of multimodal input and routes them internally across memory subsystems
  when:
    - the provider is integrated through the canonical layer
  then:
    - the canonical write path remains available while the richer ingestion path is advertised and invoked through an optional ingestion lane
  covers:
    - jido_memory.matrix.ingestion.optional_ingestion_lane
    - jido_memory.matrix.ingestion.plugin_core_only_boundary
- id: jido_memory.matrix.ingestion.extraction_reconciliation_provider_path
  given:
    - a Mem0-style provider that extracts salient memories from interaction batches and reconciles them against existing memory state
  when:
    - the provider is integrated through the canonical layer
  then:
    - the canonical remember/3 path remains available while extraction, update, delete, or no-op style maintenance semantics stay in optional ingestion lanes or provider-direct APIs
  covers:
    - jido_memory.matrix.ingestion.core_write_stability
    - jido_memory.matrix.ingestion.optional_ingestion_lane
    - jido_memory.matrix.ingestion.plugin_core_only_boundary
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/0001-additive-provider-extension-boundary.md
  covers:
    - jido_memory.matrix.ingestion.core_write_stability
    - jido_memory.matrix.ingestion.optional_ingestion_lane
    - jido_memory.matrix.ingestion.plugin_core_only_boundary
```
