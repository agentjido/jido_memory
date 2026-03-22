# Provider Surface Matrix

This subject defines how new provider-facing features are classified across the
canonical memory surface.

## Intent

Keep the canonical provider system extensible without making the required core
contract absorb every advanced memory concept.

```spec-meta
id: jido_memory.matrix.provider_surface
kind: architecture
status: draft
summary: Draft matrix for classifying memory provider features into required core, optional capability, and provider-direct lanes.
surface:
  - .spec/decisions/0001-additive-provider-extension-boundary.md
  - lib/jido_memory/provider.ex
  - lib/jido_memory/capabilities.ex
  - lib/jido_memory.ex
decisions:
  - jido_memory.provider_extension_boundary
```

## Requirements

```spec-requirements
- id: jido_memory.matrix.provider_surface.classified_extension_lanes
  statement: The provider architecture shall classify advanced features into required core, optional capability, or provider-direct lanes so new providers can add behavior without redefining the canonical contract.
  priority: must
  stability: evolving
- id: jido_memory.matrix.provider_surface.core_lane_stability
  statement: The required core lane shall stay limited to cross-provider operations that minimal and advanced providers can all satisfy without emulating specialized subsystems.
  priority: must
  stability: evolving
- id: jido_memory.matrix.provider_surface.provider_direct_escape_hatch
  statement: Provider-direct APIs shall remain a valid lane for specialized controls that are useful for a specific provider but not yet justified as canonical runtime operations.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: jido_memory.matrix.provider_surface.minimal_provider_lane
  given:
    - a minimal provider that only supports the canonical memory operations
  when:
    - the provider is classified against the matrix
  then:
    - it satisfies the required core lane without needing optional capability or provider-direct behavior
  covers:
    - jido_memory.matrix.provider_surface.classified_extension_lanes
    - jido_memory.matrix.provider_surface.core_lane_stability
- id: jido_memory.matrix.provider_surface.specialized_provider_lane
  given:
    - a specialized provider such as Mirix with active retrieval planning, multimodal ingestion, and protected memory
  when:
    - the provider is classified against the matrix
  then:
    - its common operations remain in the required core lane while its specialized controls enter through optional capabilities or provider-direct APIs
  covers:
    - jido_memory.matrix.provider_surface.classified_extension_lanes
    - jido_memory.matrix.provider_surface.provider_direct_escape_hatch
- id: jido_memory.matrix.provider_surface.extraction_reconciliation_provider_lane
  given:
    - a Mem0-style provider with extraction-and-reconciliation updates, scoped memory identities, and optional graph augmentation
  when:
    - the provider is classified against the matrix
  then:
    - canonical memory operations remain in the required core lane while extraction pipelines, scoped identity controls, and graph-specific behavior stay in optional capability or provider-direct lanes until they justify canonical treatment
  covers:
    - jido_memory.matrix.provider_surface.classified_extension_lanes
    - jido_memory.matrix.provider_surface.provider_direct_escape_hatch
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/0001-additive-provider-extension-boundary.md
  covers:
    - jido_memory.matrix.provider_surface.classified_extension_lanes
    - jido_memory.matrix.provider_surface.core_lane_stability
    - jido_memory.matrix.provider_surface.provider_direct_escape_hatch
```
