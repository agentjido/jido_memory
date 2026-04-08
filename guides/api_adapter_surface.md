# API Adapter Surface

This guide explains how the `jido_memory` surfaces fit together.

The point of the package is not just storage. The point is a stable memory API
that agents can use regardless of the backend implementation.

## The Layers

`jido_memory` has five important layers.

### 1. Runtime Facade

`Jido.Memory.Runtime` is the canonical public API.

Application and agent code should prefer this surface:

- `remember/3`
- `get/3`
- `forget/3`
- `retrieve/3`
- `capabilities/2`
- `info/2`
- `ingest/3`
- `explain_retrieval/3`
- `consolidate/2`

This layer owns:

- provider resolution
- option precedence
- normalization into canonical result structs

This layer should not own:

- backend-specific semantics
- provider-native data models
- storage engine details

### 2. Canonical Structs

The stable agent-facing data model lives in shared structs:

- `Record`
- `Query`
- `Scope`
- `Hit`
- `RetrieveResult`
- `Explanation`
- `CapabilitySet`
- `ProviderInfo`
- `IngestRequest`
- `IngestResult`
- `ConsolidationResult`

These are the most important stability boundary in the package.

If an agent or application depends on memory results, it should depend on these
structs rather than provider-specific response maps.

### 3. Plugin and Actions

`Jido.Memory.BasicPlugin` is the Jido integration adapter in core.

It adapts agent/plugin concerns into the runtime facade:

- namespace derivation
- store state for the built-in basic path
- signal routes
- optional signal auto-capture

This layer is where agent integration belongs. It should not become a second
backend abstraction.

That is why core does not ship a generic provider-aware plugin anymore. If a
provider such as MemPalace wants plugin ergonomics, it should ship them in that
provider package.

### 4. Providers

Providers adapt concrete memory implementations into the canonical runtime API.

Examples:

- `Jido.Memory.Provider.Basic`
- `Jido.Memory.Provider.MemPalace`
- `Jido.Memory.Provider.Mem0`

Providers own:

- backend-specific configuration
- retrieval semantics
- optional advanced capabilities
- mapping backend-native responses into canonical results

Providers should not redefine the application-facing API contract. They should
implement it.

### 5. Stores

Stores are a persistence substrate, not the top-level abstraction anymore.

`Jido.Memory.Provider.Basic` uses `Jido.Memory.Store` directly. Other providers
may not.

That means:

- a provider can use `Store`
- a provider can ignore `Store`
- application code should think in terms of providers first

## The Adapter Contract

The core contract is:

1. callers talk to `Runtime`
2. `Runtime` resolves a provider
3. the provider returns canonical structs or values normalizable into them
4. callers consume the canonical results

This is the key adapter story for `jido_memory`.

## Provider Resolution

Provider selection can happen through:

- explicit runtime opts
- attrs or query values
- basic plugin state
- provider defaults

Current precedence is:

1. explicit runtime opts
2. attr or query map values
3. basic plugin state
4. provider defaults

This matters because it keeps agent code stable while still allowing request-
level overrides.

## Provider Registry and References

Two modules matter here:

- `Jido.Memory.ProviderRegistry`
- `Jido.Memory.ProviderRef`

`ProviderRegistry` maps stable atom aliases to concrete modules.

Core keeps that alias set intentionally small. The built-in alias core is:

- `:basic`

External provider packages can extend the registry through application config:

```elixir
config :jido_memory, :provider_aliases,
  mempalace: Jido.Memory.Provider.MemPalace
```

`ProviderRef` is the normalized runtime form:

```elixir
%Jido.Memory.ProviderRef{
  key: :basic,
  module: Jido.Memory.Provider.Basic,
  opts: [...]
}
```

This normalized reference is what lets plugin state, runtime dispatch, and
provider packages speak the same language.

The atom `key` matters because it gives core a stable provider identity even
when callers pass a module directly.

## Optional Capability Adapters

Providers do not have to support every advanced operation.

Optional behaviors:

- `Jido.Memory.Capability.Ingestion`
- `Jido.Memory.Capability.ExplainableRetrieval`
- `Jido.Memory.Capability.Lifecycle`

`Runtime` checks whether a provider exports those callbacks and returns a stable
unsupported-capability error when it does not.

This keeps the API honest while still allowing a broad provider ecosystem.

Structured capability metadata also lives in core now:

- `CapabilitySet` exposes both flat capability atoms and a nested descriptor
- `ProviderInfo` carries provider style, topology, advanced operations, surface
  boundaries, defaults, and metadata

That richer metadata belongs in core because application code and tooling may
need to inspect it regardless of which provider package is installed.

## What Belongs In Core vs Provider Packages

Core `jido_memory` should own:

- runtime facade
- canonical structs
- provider behaviors
- provider registry and references
- plugin and action integration
- the built-in basic provider

Provider packages should own:

- backend-native data models
- backend-specific dependencies
- advanced memory-system features
- any provider-specific public APIs beyond the canonical runtime surface

Examples:

- `jido_memory_mempalace`
- `jido_memory_mem0`

## The Basic Rule

If an agent must rely on it regardless of backend, it belongs in the canonical
surface.

If it only makes sense for one backend, it belongs in that provider package.

## Related Guides

- [Using Jido.Memory](./using_jido_memory.md)
- [Basic Provider](./basic_provider.md)
- [Provider Contract](../docs/provider_contract.md)
