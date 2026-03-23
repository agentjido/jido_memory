# Provider Migration Plan

This subject defines the draft migration path from the current runtime and store model to the provider architecture.

## Intent

Make the rollout sequence explicit so implementation can proceed in additive phases without breaking existing users while moving the common advanced path into jido_memory itself.

```spec-meta
id: jido_memory.provider_migration
kind: architecture
status: draft
summary: Draft migration path for introducing the provider model, preserving current jido_memory behavior, and expanding the built-in provider set inside jido_memory while leaving jido_memory_os standalone.
surface:
  - docs/rfcs/0001-canonical-memory-provider-architecture.md
  - lib/jido_memory.ex
  - lib/jido_memory/plugin.ex
  - lib/jido_memory/store.ex
  - mix.exs
```

## Requirements

```spec-requirements
- id: jido_memory.provider_migration.basic_provider_default
  statement: The first provider implementation shall wrap the existing Jido.Memory.Runtime and Jido.Memory.Store path so current ETS-backed behavior remains the default.
  priority: must
  stability: evolving
- id: jido_memory.provider_migration.built_in_advanced_providers_in_core
  statement: The common advanced memory paths for Jido shall be implemented as built-in providers inside jido_memory, including Tiered, Mem0, and Mirix, rather than requiring jido_memory_os or an external provider as the standard advanced provider choice.
  priority: must
  stability: evolving
- id: jido_memory.provider_migration.standalone_memory_os_boundary
  statement: jido_memory_os shall remain a standalone advanced library with its native facade and plugin rather than becoming a required dependency of jido_memory for standard memory context management.
  priority: must
  stability: evolving
- id: jido_memory.provider_migration.incremental_compatibility
  statement: The provider architecture shall be introduced additively so existing runtime flows, record and store contracts, and default plugin usage continue to work while applications migrate incrementally.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: jido_memory.provider_migration.existing_ets_flow
  given:
    - an application that uses the current default ETS-backed memory flow
  when:
    - the provider architecture lands
  then:
    - the application continues to work through the Basic provider without requiring provider-specific migration
  covers:
    - jido_memory.provider_migration.basic_provider_default
    - jido_memory.provider_migration.incremental_compatibility
- id: jido_memory.provider_migration.built_in_provider_adoption
  given:
    - an application that later adopts one of the built-in advanced providers such as Tiered, Mem0, or Mirix
  when:
    - the application enables that provider through the shared plugin and runtime surface
  then:
    - the application gains advanced provider behavior without changing its agent-facing memory API or taking on a second library as the standard advanced dependency
  covers:
    - jido_memory.provider_migration.built_in_advanced_providers_in_core
    - jido_memory.provider_migration.incremental_compatibility
- id: jido_memory.provider_migration.standalone_memory_os_usage
  given:
    - an application that wants the standalone MemoryOS control plane and native workflows
  when:
    - the application adopts jido_memory_os directly
  then:
    - it continues to use MemoryOS through its native facade and plugin without forcing jido_memory to depend on that library for the common provider story
  covers:
    - jido_memory.provider_migration.standalone_memory_os_boundary
```

## Verification

```spec-verification
- kind: source_file
  target: docs/rfcs/0001-canonical-memory-provider-architecture.md
  covers:
    - jido_memory.provider_migration.basic_provider_default
    - jido_memory.provider_migration.built_in_advanced_providers_in_core
    - jido_memory.provider_migration.standalone_memory_os_boundary
    - jido_memory.provider_migration.incremental_compatibility
```
