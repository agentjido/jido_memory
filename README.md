# Jido.Memory

`Jido.Memory` is the canonical memory API package for Jido agents.

It provides:

- a stable runtime facade in `Jido.Memory.Runtime`
- canonical memory structs such as `Record`, `Query`, `Hit`, and `RetrieveResult`
- a provider contract for backend-specific implementations
- a built-in `:basic` provider backed by `Jido.Memory.Store`
- a provider-aware Jido plugin in `Jido.Memory.ETSPlugin`
- compatibility wrappers for existing `remember/get/forget/recall` flows

Advanced memory systems should integrate as provider packages rather than
stretching the core package into backend-specific semantics.

## Package Topology

Core package:

- `jido_memory`

External provider packages:

- `jido_memory_mempalace`
- `jido_memory_mem0`

The core package owns the API contract. External packages own backend-specific
implementation details and dependencies.

## Installation

Core package only:

```elixir
defp deps do
  [
    {:jido_memory, path: "../jido_memory"}
  ]
end
```

Core package with optional providers:

```elixir
defp deps do
  [
    {:jido_memory, path: "../jido_memory"},
    {:jido_memory_mempalace, path: "../jido_memory_mempalace"},
    {:jido_memory_mem0, path: "../jido_memory_mem0"}
  ]
end
```

## Canonical Runtime API

Core operations:

- `remember/3`
- `get/3`
- `forget/3`
- `retrieve/3`
- `capabilities/2`
- `info/2`
- `ingest/3`
- `explain_retrieval/3`
- `consolidate/2`

Compatibility operations:

- `recall/2` and `recall/3`
- `prune_expired/2`

### Canonical Retrieval

`retrieve/3` is the canonical read path and returns `Jido.Memory.RetrieveResult`.

```elixir
{:ok, result} =
  Jido.Memory.Runtime.retrieve(%{id: "agent-1"}, %{
    namespace: "agent:agent-1",
    text_contains: "market",
    limit: 5
  })

records = Jido.Memory.RetrieveResult.records(result)
```

`recall/2` remains available as a compatibility wrapper and returns bare
`[Jido.Memory.Record.t()]`.

```elixir
{:ok, records} =
  Jido.Memory.Runtime.recall(%{id: "agent-1"}, %{
    namespace: "agent:agent-1",
    text_contains: "market"
  })
```

### Provider Selection

The built-in default provider is `:basic`.

You can also select a provider explicitly by alias or module:

```elixir
{:ok, result} =
  Jido.Memory.Runtime.retrieve(%{id: "agent-1"}, %{text_contains: "memory"},
    provider: :basic,
    provider_opts: [
      namespace: "agent:agent-1",
      store: {Jido.Memory.Store.ETS, [table: :agent_memory]}
    ]
  )
```

When external provider packages are present, these aliases resolve through the
 runtime registry:

- `:mempalace`
- `:mem0`

## Canonical Structs

Shared structs exposed by `jido_memory`:

- `Jido.Memory.Record`
- `Jido.Memory.Query`
- `Jido.Memory.Scope`
- `Jido.Memory.Hit`
- `Jido.Memory.RetrieveResult`
- `Jido.Memory.Explanation`
- `Jido.Memory.CapabilitySet`
- `Jido.Memory.ProviderInfo`
- `Jido.Memory.IngestRequest`
- `Jido.Memory.IngestResult`
- `Jido.Memory.ConsolidationResult`

These structs are the stable shapes agents should depend on instead of backend-
specific maps.

## Built-In Basic Provider

`Jido.Memory.Provider.Basic` keeps the existing simple ETS/store path intact.

It supports:

- canonical record write/read/delete
- canonical retrieval results
- capability and provider metadata
- batch ingest
- retrieval explanation
- lifecycle consolidation via prune semantics

It uses `Jido.Memory.Store` underneath, so store adapters remain useful as
provider infrastructure.

## Jido Plugin and Actions

The package exposes a provider-aware plugin at `Jido.Memory.ETSPlugin`.

```elixir
defmodule MyApp.Agent do
  use Jido.Agent,
    name: "memory_agent",
    default_plugins: %{__memory__: false},
    plugins: [
      {Jido.Memory.ETSPlugin,
       %{
         provider: :basic,
         provider_opts: [store: {Jido.Memory.Store.ETS, [table: :my_agent_memory]}],
         namespace_mode: :per_agent,
         auto_capture: true
       }}
    ]
end
```

Signal routes:

- `memory.remember`
- `memory.retrieve`
- `memory.recall`
- `memory.forget`

Canonical action/result pairing:

- `memory.retrieve` -> `%{memory_result: %RetrieveResult{}}`
- `memory.recall` -> `%{memory_results: [%Record{}]}`

## Provider Authoring

Provider authors should implement `Jido.Memory.Provider` and, when supported,
the optional capability behaviours:

- `Jido.Memory.Capability.Ingestion`
- `Jido.Memory.Capability.ExplainableRetrieval`
- `Jido.Memory.Capability.Lifecycle`

See:

- [Provider Contract](./docs/provider_contract.md)
- [Provider-First Migration Guide](./docs/provider_migration.md)
- [Provider Migration Plan](./docs/plans/provider-memory-api-migration-plan.md)

## External Provider Packages

Two implementation packages are scaffolded in this workspace:

- `jido_memory_mempalace`
- `jido_memory_mem0`

Both currently ship a contract-compatible shim adapter so the runtime aliasing,
shared structs, and provider contract are stable before a real backend transport
is added.
