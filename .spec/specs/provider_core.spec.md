# Provider Core Contract

This subject defines the draft core contract that all pluggable memory providers must satisfy.

## Intent

Make the minimum implementable provider surface explicit before built-in tiered-memory work and any optional external providers land.

```spec-meta
id: jido_memory.provider_core
kind: architecture
status: draft
summary: Draft core provider contract for configuration-driven pluggable memory providers in jido_memory, including built-in provider choices.
surface:
  - docs/rfcs/0001-canonical-memory-provider-architecture.md
  - lib/jido_memory.ex
  - lib/jido_memory/plugin.ex
  - lib/jido_memory/store.ex
```

## Requirements

```spec-requirements
- id: jido_memory.provider_core.required_behaviour
  statement: The canonical provider layer shall define a required core behaviour that covers configuration validation, child spec declaration, initialization, capability reporting, and the base remember, get, retrieve, forget, prune, and info operations.
  priority: must
  stability: evolving
- id: jido_memory.provider_core.bootstrap_boundary
  statement: Providers shall own their own bootstrap boundary through core callbacks so advanced implementations can attach supervision and provider metadata without leaking implementation-specific startup details into the facade.
  priority: must
  stability: evolving
- id: jido_memory.provider_core.provider_bundle_selection
  statement: Applications shall select memory implementations as provider bundles exposed through jido_memory, whether those bundles point at built-in providers or explicit external modules, rather than wiring low-level implementation details directly into agent code.
  priority: must
  stability: evolving
- id: jido_memory.provider_core.built_in_provider_catalog
  statement: jido_memory shall expose a stable built-in provider catalog for the common memory strategies it owns, so users can select those providers without importing additional libraries for the standard Jido memory path.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: jido_memory.provider_core.basic_provider_bootstrap
  given:
    - a default Basic provider configuration backed by the current runtime and store path
  when:
    - the provider is initialized through the canonical contract
  then:
    - the provider returns core capability metadata and any startup requirements through the required callbacks
  covers:
    - jido_memory.provider_core.required_behaviour
    - jido_memory.provider_core.bootstrap_boundary
    - jido_memory.provider_core.built_in_provider_catalog
- id: jido_memory.provider_core.tiered_provider_bootstrap
  given:
    - a built-in Tiered provider configuration with short, mid, and long memory concerns
  when:
    - the provider is initialized through the canonical contract
  then:
    - the provider reports its tiered capability metadata and any startup requirements through the same core callback surface
  covers:
    - jido_memory.provider_core.required_behaviour
    - jido_memory.provider_core.bootstrap_boundary
    - jido_memory.provider_core.built_in_provider_catalog
- id: jido_memory.provider_core.external_provider_bootstrap
  given:
    - an optional external provider that needs its own supervised components
  when:
    - the canonical facade resolves and initializes that provider
  then:
    - provider metadata and child specs enter through provider callbacks rather than plugin-specific special cases
  covers:
    - jido_memory.provider_core.bootstrap_boundary
    - jido_memory.provider_core.provider_bundle_selection
```

## Verification

```spec-verification
- kind: source_file
  target: docs/rfcs/0001-canonical-memory-provider-architecture.md
  covers:
    - jido_memory.provider_core.required_behaviour
    - jido_memory.provider_core.bootstrap_boundary
    - jido_memory.provider_core.provider_bundle_selection
    - jido_memory.provider_core.built_in_provider_catalog
```
