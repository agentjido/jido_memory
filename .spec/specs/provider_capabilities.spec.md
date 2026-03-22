# Provider Capability Contract

This subject defines the draft capability model that sits on top of the required provider core.

## Intent

Separate optional advanced behaviors from the minimum provider contract so built-in and optional external providers can coexist cleanly.

```spec-meta
id: jido_memory.provider_capabilities
kind: architecture
status: draft
summary: Draft capability model for optional memory provider behaviors, discovery, and unsupported-capability handling.
surface:
  - docs/rfcs/0001-canonical-memory-provider-architecture.md
  - lib/jido_memory.ex
  - lib/jido_memory/plugin.ex
  - lib/jido_memory/store.ex
decisions:
  - jido_memory.provider_extension_boundary
```

## Requirements

```spec-requirements
- id: jido_memory.provider_capabilities.optional_behaviours
  statement: Advanced memory features shall be expressed as optional capability behaviours separate from the required provider core contract.
  priority: must
  stability: evolving
- id: jido_memory.provider_capabilities.additive_extension_boundary
  statement: New advanced provider features shall enter the canonical layer additively through optional capability families or provider-native extensions rather than by enlarging the required provider core with specialized concerns.
  priority: must
  stability: evolving
- id: jido_memory.provider_capabilities.structured_discovery
  statement: Providers shall expose capabilities as structured metadata rather than an untyped flat list so tooling and facades can reason about supported features.
  priority: must
  stability: evolving
- id: jido_memory.provider_capabilities.ingestion_capability_family
  statement: The capability model shall support a distinct ingestion-oriented capability family so batch, multimodal, and routed write flows can be negotiated separately from the core remember/3 contract.
  priority: must
  stability: evolving
- id: jido_memory.provider_capabilities.explainability_routing_trace_boundary
  statement: Providers may expose retrieval plans, routing traces, and other provider-native explanation details through explainability metadata without changing the canonical retrieve/3 result shape.
  priority: must
  stability: evolving
- id: jido_memory.provider_capabilities.governance_protected_memory
  statement: Protected or exact-preservation memory semantics, such as vault-style storage, shall be modeled through governance capabilities or provider-direct APIs rather than required behavior for all providers.
  priority: must
  stability: evolving
- id: jido_memory.provider_capabilities.typed_unsupported_error
  statement: The canonical layer shall return a typed unsupported-capability error when a caller requests a capability the configured provider does not implement.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: jido_memory.provider_capabilities.explainability_negotiation
  given:
    - a configured provider that supports core retrieval but not explainable retrieval
  when:
    - a caller asks the canonical layer for retrieval explanation
  then:
    - the request fails with a typed unsupported-capability error rather than a silent no-op
  covers:
    - jido_memory.provider_capabilities.optional_behaviours
    - jido_memory.provider_capabilities.typed_unsupported_error
- id: jido_memory.provider_capabilities.tiered_provider_inspection
  given:
    - a built-in Tiered provider that supports lifecycle and tier-aware retrieval features
  when:
    - tooling inspects the provider capability map
  then:
    - the supported lifecycle and retrieval features are discoverable as structured metadata without changing the core provider contract
  covers:
    - jido_memory.provider_capabilities.optional_behaviours
    - jido_memory.provider_capabilities.structured_discovery
- id: jido_memory.provider_capabilities.multimodal_ingestion_negotiation
  given:
    - a provider that supports batch multimodal ingestion in addition to the canonical core write path
  when:
    - tooling inspects the provider capability map
  then:
    - ingestion support is discoverable through a dedicated optional capability family instead of changing the core remember/3 contract
  covers:
    - jido_memory.provider_capabilities.additive_extension_boundary
    - jido_memory.provider_capabilities.ingestion_capability_family
    - jido_memory.provider_capabilities.structured_discovery
- id: jido_memory.provider_capabilities.routing_trace_negotiation
  given:
    - a provider that performs active retrieval planning and memory-type routing
  when:
    - the caller asks for retrieval explanation through the canonical layer
  then:
    - the provider can return routing traces and planning metadata as explainability output without changing the canonical retrieve/3 return shape
  covers:
    - jido_memory.provider_capabilities.additive_extension_boundary
    - jido_memory.provider_capabilities.explainability_routing_trace_boundary
- id: jido_memory.provider_capabilities.protected_memory_negotiation
  given:
    - a provider that includes protected exact-preservation memory
  when:
    - the provider advertises its advanced feature set
  then:
    - the protected memory semantics are represented through governance capability metadata or provider-direct APIs instead of becoming a mandatory part of the shared core provider contract
  covers:
    - jido_memory.provider_capabilities.additive_extension_boundary
    - jido_memory.provider_capabilities.governance_protected_memory
```

## Verification

```spec-verification
- kind: source_file
  target: docs/rfcs/0001-canonical-memory-provider-architecture.md
  covers:
    - jido_memory.provider_capabilities.optional_behaviours
    - jido_memory.provider_capabilities.structured_discovery
    - jido_memory.provider_capabilities.typed_unsupported_error
- kind: source_file
  target: .spec/decisions/0001-additive-provider-extension-boundary.md
  covers:
    - jido_memory.provider_capabilities.additive_extension_boundary
    - jido_memory.provider_capabilities.ingestion_capability_family
    - jido_memory.provider_capabilities.explainability_routing_trace_boundary
    - jido_memory.provider_capabilities.governance_protected_memory
    - jido_memory.provider_capabilities.typed_unsupported_error
```
