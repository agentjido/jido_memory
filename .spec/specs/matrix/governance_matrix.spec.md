# Governance Matrix

This subject defines how protected memory semantics fit into the provider
architecture without becoming mandatory for all providers.

## Intent

Allow specialized providers to support protected or exact-preservation memory
while keeping the canonical core usable for providers that do not need those
concepts.

```spec-meta
id: jido_memory.matrix.governance
kind: architecture
status: draft
summary: Draft matrix for governance and protected-memory features in pluggable memory providers.
surface:
  - .spec/decisions/0001-additive-provider-extension-boundary.md
  - lib/jido_memory/capability/governance.ex
  - lib/jido_memory.ex
  - lib/jido_memory/provider.ex
decisions:
  - jido_memory.provider_extension_boundary
```

## Requirements

```spec-requirements
- id: jido_memory.matrix.governance.protected_memory_lane
  statement: Protected or exact-preservation memory semantics shall live in governance capability metadata or provider-direct APIs rather than in the required provider core.
  priority: must
  stability: evolving
- id: jido_memory.matrix.governance.no_mandatory_vault_core
  statement: Providers that do not implement vault-style semantics shall not be required to emulate protected memory in order to satisfy the canonical provider contract.
  priority: must
  stability: evolving
- id: jido_memory.matrix.governance.selective_runtime_exposure
  statement: The common runtime shall expose governance behavior only when the operation is broadly reusable, leaving more specialized protected-memory controls to provider-direct surfaces until they justify canonical treatment.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: jido_memory.matrix.governance.basic_provider_boundary
  given:
    - a provider that does not support protected memory semantics
  when:
    - the provider is evaluated against the canonical contract
  then:
    - it remains valid without implementing vault-style behavior
  covers:
    - jido_memory.matrix.governance.no_mandatory_vault_core
- id: jido_memory.matrix.governance.protected_memory_provider_boundary
  given:
    - a provider that stores exact-preservation facts separately from general memory
  when:
    - the provider is integrated through the canonical layer
  then:
    - the protected-memory semantics are expressed through governance metadata or provider-direct APIs without enlarging the required provider core
  covers:
    - jido_memory.matrix.governance.protected_memory_lane
    - jido_memory.matrix.governance.selective_runtime_exposure
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/0001-additive-provider-extension-boundary.md
  covers:
    - jido_memory.matrix.governance.protected_memory_lane
    - jido_memory.matrix.governance.no_mandatory_vault_core
    - jido_memory.matrix.governance.selective_runtime_exposure
```
