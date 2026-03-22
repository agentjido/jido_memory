# Provider Facade Contract

This subject defines the draft facade and plugin boundary that applications use regardless of the selected provider.

## Intent

Keep the agent-facing memory API stable while allowing built-in and optional external provider implementations to vary behind that boundary.

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
decisions:
  - jido_memory.provider_extension_boundary
```

## Requirements

```spec-requirements
- id: jido_memory.provider_facade.provider_configurable_plugin
  statement: Jido.Memory.Plugin shall be the unified memory-context entrypoint for Jido agents and shall be provider-configurable so the same agent-facing plugin and action API can target different memory implementations.
  priority: must
  stability: evolving
- id: jido_memory.provider_facade.canonical_dispatch_boundary
  statement: Actions and runtime-facing helpers shall dispatch through a canonical memory facade rather than calling provider-specific modules directly.
  priority: must
  stability: evolving
- id: jido_memory.provider_facade.narrow_runtime_boundary
  statement: The common runtime facade shall stay selective, standardizing only broadly reusable operations while leaving provider-specific manager controls, retrieval plans, and specialized workflows to capability-specific helpers, info payloads, or provider-direct APIs.
  priority: must
  stability: evolving
- id: jido_memory.provider_facade.shared_record_query_contract
  statement: Jido.Memory.Record and the base Jido.Memory.Query contract shall remain canonical, while provider-specific retrieval features stay in backward-compatible options or hints rather than mandatory core fields.
  priority: must
  stability: evolving
- id: jido_memory.provider_facade.provider_native_extension_boundary
  statement: Provider-specific retrieval or ingestion features shall travel through optional hints, explainability payloads, or provider-direct APIs so the shared plugin and runtime surface stays stable across basic, tiered, and more specialized providers.
  priority: must
  stability: evolving
- id: jido_memory.provider_facade.built_in_provider_selection
  statement: The common plugin and runtime configuration shall allow library users to select built-in provider choices shipped by jido_memory without changing agent memory calls or depending on a second library for the standard advanced path.
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
    - the default Basic provider path preserves the current ETS-backed experience behind the canonical facade
  covers:
    - jido_memory.provider_facade.provider_configurable_plugin
    - jido_memory.provider_facade.canonical_dispatch_boundary
    - jido_memory.provider_facade.built_in_provider_selection
- id: jido_memory.provider_facade.built_in_tiered_provider_path
  given:
    - a plugin configuration that selects the built-in Tiered provider
  when:
    - agent memory actions are executed
  then:
    - the agent-facing API remains stable while tiered behavior stays behind the canonical facade and shared record and query contracts
  covers:
    - jido_memory.provider_facade.provider_configurable_plugin
    - jido_memory.provider_facade.canonical_dispatch_boundary
    - jido_memory.provider_facade.shared_record_query_contract
    - jido_memory.provider_facade.built_in_provider_selection
- id: jido_memory.provider_facade.built_in_mirix_provider_path
  given:
    - a plugin configuration that selects the built-in Mirix provider
  when:
    - agent memory actions are executed through the common plugin and runtime surface
  then:
    - the shared agent-facing API remains stable for canonical memory operations while routed retrieval explanations stay on the common facade and ingestion or protected-memory workflows remain provider-direct
  covers:
    - jido_memory.provider_facade.provider_configurable_plugin
    - jido_memory.provider_facade.canonical_dispatch_boundary
    - jido_memory.provider_facade.narrow_runtime_boundary
    - jido_memory.provider_facade.provider_native_extension_boundary
    - jido_memory.provider_facade.built_in_provider_selection
- id: jido_memory.provider_facade.external_provider_path
  given:
    - a plugin configuration that selects an explicit external provider bundle
  when:
    - agent memory actions are executed
  then:
    - the same plugin and runtime surface dispatch through the canonical facade without introducing provider-specific call sites into agent code
  covers:
    - jido_memory.provider_facade.provider_configurable_plugin
    - jido_memory.provider_facade.canonical_dispatch_boundary
- id: jido_memory.provider_facade.specialized_provider_extension_path
  given:
    - a specialized provider that offers multimodal ingestion, active retrieval planning, or protected memory
  when:
    - the provider is used through the common plugin and runtime surface for shared memory operations
  then:
    - shared calls remain stable while specialized behavior is exposed through capability-specific helpers, explainability output, info payloads, or provider-direct APIs
  covers:
    - jido_memory.provider_facade.narrow_runtime_boundary
    - jido_memory.provider_facade.provider_native_extension_boundary
    - jido_memory.provider_facade.shared_record_query_contract
- id: jido_memory.provider_facade.mem0_style_provider_path
  given:
    - a plugin configuration that selects a Mem0-style provider
  when:
    - agent memory actions are executed through the common plugin and runtime surface
  then:
    - the shared agent-facing API remains stable for canonical memory operations while extraction-and-reconciliation updates, scoped identity controls, and graph-augmented retrieval details stay behind explainability metadata, provider config, or provider-direct APIs
  covers:
    - jido_memory.provider_facade.provider_configurable_plugin
    - jido_memory.provider_facade.narrow_runtime_boundary
    - jido_memory.provider_facade.provider_native_extension_boundary
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
    - jido_memory.provider_facade.built_in_provider_selection
- kind: source_file
  target: .spec/decisions/0001-additive-provider-extension-boundary.md
  covers:
    - jido_memory.provider_facade.narrow_runtime_boundary
    - jido_memory.provider_facade.provider_native_extension_boundary
    - jido_memory.provider_facade.shared_record_query_contract
```
