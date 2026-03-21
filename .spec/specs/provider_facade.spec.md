# Provider Facade Contract

This subject defines the draft facade and plugin boundary that applications use regardless of the selected provider.

## Intent

Keep the agent-facing memory API stable while allowing provider implementations to vary behind that boundary.

```spec-meta
id: jido_memory.provider_facade
kind: architecture
status: draft
summary: Draft facade contract for provider-configurable plugins, canonical dispatch, and shared record and query types.
surface:
  - docs/rfcs/0001-canonical-memory-provider-architecture.md
  - README.md
  - lib/jido_memory.ex
  - lib/jido_memory/plugin.ex
  - lib/jido_memory/actions/*.ex
  - lib/jido_memory/query.ex
  - lib/jido_memory/record.ex
```

## Requirements

```spec-requirements
- id: jido_memory.provider_facade.provider_configurable_plugin
  statement: Jido.Memory.Plugin shall be provider-configurable so the same agent-facing plugin and action API can target different memory implementations.
  priority: must
  stability: evolving
- id: jido_memory.provider_facade.canonical_dispatch_boundary
  statement: Actions and runtime-facing helpers shall dispatch through a canonical memory facade rather than calling provider-specific modules directly.
  priority: must
  stability: evolving
- id: jido_memory.provider_facade.shared_record_query_contract
  statement: Jido.Memory.Record and the base Jido.Memory.Query contract shall remain canonical, while provider-specific retrieval features stay in backward-compatible options or hints rather than mandatory core fields.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: jido_memory.provider_facade.default_basic_provider_path
  given:
    - a plugin configuration that does not explicitly select a provider
  when:
    - the plugin is mounted for an agent
  then:
    - the default basic provider path preserves the current ETS-backed experience behind the canonical facade
  covers:
    - jido_memory.provider_facade.provider_configurable_plugin
    - jido_memory.provider_facade.canonical_dispatch_boundary
- id: jido_memory.provider_facade.advanced_provider_path
  given:
    - a plugin configuration that selects an advanced provider bundle
  when:
    - agent memory actions are executed
  then:
    - the agent-facing API remains stable while provider-specific behavior stays behind the canonical facade and shared record and query contracts
  covers:
    - jido_memory.provider_facade.provider_configurable_plugin
    - jido_memory.provider_facade.canonical_dispatch_boundary
    - jido_memory.provider_facade.shared_record_query_contract
```

## Verification

```spec-verification
- kind: source_file
  target: docs/rfcs/0001-canonical-memory-provider-architecture.md
  covers:
    - jido_memory.provider_facade.provider_configurable_plugin
    - jido_memory.provider_facade.canonical_dispatch_boundary
    - jido_memory.provider_facade.shared_record_query_contract
```
