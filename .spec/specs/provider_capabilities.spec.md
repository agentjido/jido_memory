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
```

## Requirements

```spec-requirements
- id: jido_memory.provider_capabilities.optional_behaviours
  statement: Advanced memory features shall be expressed as optional capability behaviours separate from the required provider core contract.
  priority: must
  stability: evolving
- id: jido_memory.provider_capabilities.structured_discovery
  statement: Providers shall expose capabilities as structured metadata rather than an untyped flat list so tooling and facades can reason about supported features.
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
```

## Verification

```spec-verification
- kind: source_file
  target: docs/rfcs/0001-canonical-memory-provider-architecture.md
  covers:
    - jido_memory.provider_capabilities.optional_behaviours
    - jido_memory.provider_capabilities.structured_discovery
    - jido_memory.provider_capabilities.typed_unsupported_error
```
