# Canonical Memory Provider Architecture

This subject records the current repository-level direction for the provider architecture.

## Intent

Keep the provider architecture proposal explicit and reviewable while the implementation continues to evolve.

Detailed implementation subjects are tracked separately in:

- `.spec/specs/provider_core.spec.md`
- `.spec/specs/provider_capabilities.spec.md`
- `.spec/specs/provider_facade.spec.md`
- `.spec/specs/provider_migration.spec.md`

```spec-meta
id: jido_memory.provider_architecture
kind: architecture
status: draft
summary: Draft provider architecture for making jido_memory the unified Jido memory package with built-in provider choices such as Basic, Tiered, and Mirix, while leaving jido_memory_os as a standalone advanced library.
surface:
  - docs/rfcs/0001-canonical-memory-provider-architecture.md
  - lib/jido_memory.ex
  - lib/jido_memory/store.ex
  - lib/jido_memory/plugin.ex
```

## Requirements

```spec-requirements
- id: jido_memory.provider_architecture.contract_owner
  statement: The canonical provider architecture proposal shall place the shared provider contract in jido_memory rather than in an implementation-specific advanced library.
  priority: must
  stability: evolving
- id: jido_memory.provider_architecture.core_plus_capabilities
  statement: The proposal shall separate required core provider operations from optional capability behaviors so minimal and advanced providers can coexist without a single oversized interface.
  priority: must
  stability: evolving
- id: jido_memory.provider_architecture.built_in_provider_choices
  statement: The proposal shall make jido_memory the package that ships the standard provider choices needed for unified memory context management in Jido, instead of requiring a second library for the common advanced path.
  priority: must
  stability: evolving
- id: jido_memory.provider_architecture.provider_roles
  statement: The proposal shall treat the current runtime and store stack as the Basic provider path, position a native Tiered provider in jido_memory as the standard built-in tiered path, support a native Mirix provider in jido_memory as the built-in routed memory-type path, and leave jido_memory_os as a standalone advanced library with optional future interop rather than a required core dependency.
  priority: must
  stability: evolving
```

## Verification

```spec-verification
- kind: source_file
  target: docs/rfcs/0001-canonical-memory-provider-architecture.md
  covers:
    - jido_memory.provider_architecture.contract_owner
    - jido_memory.provider_architecture.core_plus_capabilities
    - jido_memory.provider_architecture.built_in_provider_choices
    - jido_memory.provider_architecture.provider_roles
```
