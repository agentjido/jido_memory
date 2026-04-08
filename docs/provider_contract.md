# Provider Contract

This document defines the public provider contract for `jido_memory`.

## Core Behaviour

Providers must implement `Jido.Memory.Provider`.

Required callbacks:

- `validate_config/1`
- `capabilities/1`
- `remember/3`
- `get/3`
- `retrieve/3`
- `forget/3`
- `prune/2`
- `info/2`

Optional callback:

- `child_specs/1`

`retrieve/3` must return `{:ok, %Jido.Memory.RetrieveResult{}}`.

## Optional Capability Behaviours

Providers can implement these capability behaviours when supported:

- `Jido.Memory.Capability.Ingestion`
- `Jido.Memory.Capability.ExplainableRetrieval`
- `Jido.Memory.Capability.Lifecycle`

If a provider does not implement a capability callback, `Jido.Memory.Runtime`
returns `{:error, {:unsupported_capability, capability, provider_module}}`.

## Canonical Result Types

Provider implementations should return these canonical structs:

- retrieval: `Jido.Memory.RetrieveResult`
- capabilities: `Jido.Memory.CapabilitySet`
- provider metadata: `Jido.Memory.ProviderInfo`
- ingest: `Jido.Memory.IngestResult`
- explanation: `Jido.Memory.Explanation`
- lifecycle: `Jido.Memory.ConsolidationResult`

Compatibility note:

- `Jido.Memory.Runtime` will normalize maps into canonical structs where
  possible, but providers should return the structs directly.

`CapabilitySet` is more than a flat atom list. Providers should use it to expose:

- supported flat capability atoms
- a structured capability descriptor
- a canonical provider key when one exists
- provider-specific capability metadata when useful

`ProviderInfo` is the canonical provider metadata surface. It can describe:

- canonical provider key
- provider style or family
- structured capability descriptor
- topology and resolved defaults
- advanced provider-direct operations
- surface boundaries between runtime, plugin, and provider-native APIs

## Provider Aliases

Core aliases exposed by `Jido.Memory.ProviderRegistry`:

- `:basic`

External provider packages can extend the atom alias registry through config:

```elixir
config :jido_memory, :provider_aliases,
  custom_provider: MyApp.Memory.Provider,
  mempalace: Jido.Memory.Provider.MemPalace
```

## Configuration Rules

Provider option precedence is:

1. explicit runtime opts
2. query or attr map values
3. plugin state
4. provider defaults

Provider implementations should keep this in mind when they merge backend-
specific options internally.

## Bootstrap

Providers that require supervised infrastructure should expose `child_specs/1`.

Callers can inspect bootstrap requirements through
`Jido.Memory.ProviderBootstrap.child_specs/2`.

Core runtime does not start provider infrastructure automatically.

## Contract Tests

Provider packages should use `Jido.Memory.Testing.ProviderContractCase` in their
test suite.

This verifies:

- capability exposure
- provider metadata
- remember/get/retrieve/forget lifecycle
- optional capability wrappers when supported

## Minimal Provider Skeleton

```elixir
defmodule MyApp.Memory.Provider do
  @behaviour Jido.Memory.Provider

  alias Jido.Memory.{CapabilitySet, ProviderInfo, RetrieveResult}

  @impl true
  def validate_config(opts), do: :ok

  @impl true
  def capabilities(_opts) do
    {:ok,
     CapabilitySet.new!(%{
       provider: __MODULE__,
       key: :custom,
       capabilities: [:remember, :get, :retrieve],
       descriptor: %{
         retrieval: %{basic: true},
         storage: %{durable: false}
       }
     })}
  end

  @impl true
  def info(_opts, _fields) do
    {:ok,
     ProviderInfo.new!(%{
       name: "custom",
       key: :custom,
       provider: __MODULE__,
       provider_style: :custom,
       capabilities: [:retrieve],
       capability_descriptor: %{
         retrieval: %{basic: true}
       },
       topology: %{storage: :memory_only},
       surface_boundary: %{runtime: [:remember, :retrieve]}
     })}
  end

  @impl true
  def retrieve(_target, _query, _opts) do
    {:ok, RetrieveResult.new!(%{hits: []})}
  end

  # implement remaining callbacks...
end
```
