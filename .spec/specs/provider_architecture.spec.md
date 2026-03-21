# Canonical Memory Provider Architecture

This subject records the current repository-level direction for the proposed provider architecture.

## Intent

Keep the provider architecture proposal explicit and reviewable while the implementation still lives in design form.

```spec-meta
id: jido_memory.provider_architecture
kind: architecture
status: draft
summary: Draft provider architecture for making jido_memory the canonical contract layer and allowing pluggable memory implementations such as a basic provider and jido_memory_os.
surface:
  - docs/rfcs/0001-canonical-memory-provider-architecture.md
  - lib/jido_memory.ex
  - lib/jido_memory/store.ex
  - lib/jido_memory/plugin.ex
```

## Requirements

```spec-requirements
- id: jido_memory.provider_architecture.contract_owner
  statement: The canonical provider architecture proposal shall place the shared provider contract in jido_memory rather than in an implementation-specific advanced provider.
  priority: must
  stability: evolving
- id: jido_memory.provider_architecture.core_plus_capabilities
  statement: The proposal shall separate required core provider operations from optional capability behaviors so minimal and advanced providers can coexist without a single oversized interface.
  priority: must
  stability: evolving
- id: jido_memory.provider_architecture.provider_roles
  statement: The proposal shall treat the current runtime and store stack as the basic provider path and position jido_memory_os as an advanced provider implementation of the shared contract.
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
    - jido_memory.provider_architecture.provider_roles
```
