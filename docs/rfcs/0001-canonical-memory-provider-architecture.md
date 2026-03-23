# RFC 0001: Canonical Memory Provider Architecture

- Status: Draft
- Date: 2026-03-21
- Target library: `jido_memory`

## Summary

This RFC proposes that `jido_memory` become the unified memory package for Jido agents.

<!-- covers: jido_memory.provider_architecture.contract_owner -->
<!-- covers: jido_memory.provider_architecture.built_in_provider_choices -->
<!-- covers: spec.workspace.current_truth_boundary -->

Instead of treating `jido_memory_os` as the required advanced provider path, we define
`jido_memory` as the package that owns both the shared contract and the standard built-in
provider choices for agent memory context management.

That means applications can choose a memory implementation at configuration time through one package:

- a minimal `Basic` provider backed by the current `Jido.Memory.Runtime` and `Jido.Memory.Store`
- a built-in `Tiered` provider that brings core short, mid, and long memory principles into `jido_memory`
- a built-in `Mem0` provider for extraction-and-reconciliation memory with scoped retrieval and provider-direct maintenance workflows
- a built-in `Mirix` provider for routed memory-type retrieval, provider-direct ingestion, and protected vault workflows
- optional future external providers for graph, vector, remote-service, or domain-specific memory systems

The design centers on:

- a required core provider behaviour
- optional capability behaviours
- a stable plugin and actions facade in `jido_memory`
- built-in provider choices as the standard Jido memory path
- optional external providers behind the same provider boundary
- `jido_memory_os` remaining a standalone advanced library rather than a required dependency

<!-- covers: jido_memory.provider_architecture.core_plus_capabilities -->
<!-- covers: jido_memory.provider_architecture.provider_roles -->
<!-- covers: jido_memory.provider_core.provider_bundle_selection -->
<!-- covers: jido_memory.provider_capabilities.optional_behaviours -->

## Motivation

Today the two libraries split responsibilities in a useful but incomplete way:

- `jido_memory` already owns the canonical record and store substrate:
  - `Jido.Memory.Record`
  - `Jido.Memory.Query`
  - `Jido.Memory.Store`
  - `Jido.Memory.Runtime`
- `jido_memory_os` adds advanced orchestration:
  - tiered memory
  - control plane
  - explainable retrieval
  - governance
  - journaling and replay
  - migration and rollout support

That split has been useful for experimentation, but it leaves the common Jido memory story in an awkward place:

- the stable data model lives in `jido_memory`
- the common plugin and runtime surface should also live in `jido_memory`
- but the standard advanced memory path currently points out to a second library

If the goal is for `jido_memory` to provide a unified way to manage memory context in Jido,
then the standard provider choices need to live there too.

This RFC therefore shifts the design center slightly:

- `jido_memory` owns the contract and the built-in provider catalog
- `jido_memory` provides the standard provider choices for common Jido memory use cases
- `jido_memory_os` remains a standalone advanced library for users who want its native control plane and workflows

## Goals

- Define a stable agent-facing memory contract in `jido_memory`
- Allow applications to select a memory provider by configuration
- Make `jido_memory` the package that ships the standard built-in provider choices
- Preserve `Jido.Memory.Record` as the canonical shared record model
- Keep the common plugin and actions surface stable across providers
- Support optional advanced capabilities without forcing every provider to implement them
- Leave room for future optional external providers that do not use tiers internally

## Non-Goals

- Standardizing one internal memory layout for all providers
- Requiring every provider to implement tiering, replay, governance, or explainability
- Merging the full `jido_memory_os` control plane into `jido_memory`
- Making `jido_memory` depend on `jido_memory_os`
- Replacing the existing `Jido.Memory.Store` abstraction in the first step
- Solving vector retrieval, graph retrieval, and lifecycle strategies exhaustively in this RFC

## Design Principles

### 1. Standardize operations, not internals

The common contract should express what a memory implementation can do, not how it stores
or organizes memory.

This is important because:

- the current `jido_memory` model is flat and namespace-based
- the built-in Tiered provider will be lifecycle-driven
- future providers may be graph-based, vector-first, or remote

### 2. Bundle-first, component-second

The main public swap point should be the provider bundle:

- `Basic`
- `Tiered`
- `GraphMemory`
- `RemoteMemory`

Within a provider, internal composition can remain modular:

- storage backend
- retrieval planner
- ranking module
- lifecycle module
- long-term store module

This avoids exposing a fragile compatibility matrix to applications too early.

### 3. Capabilities over one giant interface

Every provider should satisfy the same core contract.
Advanced features should be negotiated by capability, not forced into one oversized behaviour.

### 4. Built-ins for the standard path, externals for specialization

The standard provider choices for Jido agent memory should be shipped inside `jido_memory`.
External providers remain welcome, but the common path should not require a second library.

<!-- covers: jido_memory.provider_core.built_in_provider_catalog -->
<!-- covers: jido_memory.provider_facade.built_in_provider_selection -->

### 5. Behaviours over protocols

Provider selection is configuration-driven, not data-type-driven.
That makes Elixir behaviours the right abstraction, while protocols would be the wrong fit.

## Proposed Architecture

```mermaid
flowchart LR
    App["App / Agent"] --> Plugin["Jido.Memory.Plugin"]
    Plugin --> Facade["Jido.Memory facade/runtime"]
    Facade --> Selector["Provider selection"]

    Selector --> Basic["Built-in Basic provider"]
    Selector --> Tiered["Built-in Tiered provider"]
    Selector --> External["Optional external provider"]

    Basic --> Core["Required Provider Behaviour"]
    Tiered --> Core
    External --> Core

    Tiered --> Cap1["Optional Lifecycle Behaviour"]
    Tiered --> Cap2["Optional Explainability Behaviour"]
    External --> Cap3["Optional Capability Behaviours"]
```

## Proposed Modules

### Required

- `Jido.Memory.Provider`
- `Jido.Memory.Provider.Basic`
- `Jido.Memory.Provider.Tiered`

### Optional capability behaviours

- `Jido.Memory.Capability.Lifecycle`
- `Jido.Memory.Capability.ExplainableRetrieval`
- `Jido.Memory.Capability.Operations`
- `Jido.Memory.Capability.Governance`
- `Jido.Memory.Capability.TurnHooks`

### Supporting modules

- `Jido.Memory.ProviderRef`
- `Jido.Memory.Capabilities`
- `Jido.Memory.Error.UnsupportedCapability`
- `Jido.Memory.LongTermStore` or an equivalent long-term persistence behaviour for the Tiered provider

## Required Provider Behaviour

The core behaviour should cover the minimum contract that all memory systems can reasonably satisfy.

<!-- covers: jido_memory.provider_core.required_behaviour -->
<!-- covers: jido_memory.provider_core.bootstrap_boundary -->

```elixir
defmodule Jido.Memory.Provider do
  alias Jido.Memory.Query
  alias Jido.Memory.Record

  @type target :: map() | struct()
  @type provider_meta :: map()

  @callback validate_config(keyword()) :: :ok | {:error, term()}
  @callback child_specs(keyword()) :: [Supervisor.child_spec()]
  @callback init(keyword()) :: {:ok, provider_meta()} | {:error, term()}
  @callback capabilities(provider_meta()) :: map()

  @callback remember(target(), map() | keyword(), keyword()) ::
              {:ok, Record.t()} | {:error, term()}

  @callback get(target(), String.t(), keyword()) ::
              {:ok, Record.t()} | {:error, term()}

  @callback retrieve(target(), Query.t() | map() | keyword(), keyword()) ::
              {:ok, [Record.t()]} | {:error, term()}

  @callback forget(target(), String.t(), keyword()) ::
              {:ok, boolean()} | {:error, term()}

  @callback prune(target(), keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @callback info(provider_meta(), :all | [atom()]) :: {:ok, map()} | {:error, term()}
end
```

### Rationale

- `child_specs/1` lets advanced providers bring their own supervision tree when needed
- `init/1` returns provider metadata that the plugin and runtime can retain
- `capabilities/1` gives a structured way to expose supported features
- `info/2` gives one stable place for implementation metadata and health

## Optional Capability Behaviours

<!-- covers: jido_memory.provider_capabilities.optional_behaviours -->

### Lifecycle

```elixir
defmodule Jido.Memory.Capability.Lifecycle do
  @callback consolidate(map() | struct(), keyword()) ::
              {:ok, map()} | {:error, term()}
end
```

### Explainable Retrieval

```elixir
defmodule Jido.Memory.Capability.ExplainableRetrieval do
  @callback explain_retrieval(map() | struct(), term(), keyword()) ::
              {:ok, map()} | {:error, term()}
end
```

### Operations

```elixir
defmodule Jido.Memory.Capability.Operations do
  @callback metrics(keyword()) :: {:ok, map()} | {:error, term()}
  @callback audit_events(keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback journal_events(keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback cancel_pending(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
end
```

### Governance

```elixir
defmodule Jido.Memory.Capability.Governance do
  @callback issue_approval_token(keyword()) :: {:ok, map()} | {:error, term()}
  @callback current_policy(keyword()) :: {:ok, map()} | {:error, term()}
end
```

### Turn Hooks

```elixir
defmodule Jido.Memory.Capability.TurnHooks do
  @callback pre_turn(map() | struct(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback post_turn(map() | struct(), keyword()) :: {:ok, map()} | {:error, term()}
end
```

## Capability Discovery

Providers should expose capabilities as structured data rather than a flat list of atoms.

<!-- covers: jido_memory.provider_capabilities.structured_discovery -->
<!-- covers: jido_memory.provider_capabilities.typed_unsupported_error -->

Example:

```elixir
%{
  core: true,
  retrieval: %{
    explainable: true,
    tiers: true
  },
  lifecycle: %{
    consolidate: true,
    promote: true
  },
  operations: %{
    metrics: true
  }
}
```

The stable plugin and runtime layer can use this to:

- expose routes only when supported
- return a typed unsupported-capability error
- surface provider metadata to tooling

## Plugin and Runtime Changes

`jido_memory` should own the stable plugin and actions facade.

<!-- covers: jido_memory.provider_facade.provider_configurable_plugin -->
<!-- covers: jido_memory.provider_facade.canonical_dispatch_boundary -->

### Proposed direction

- `Jido.Memory.Plugin` becomes provider-configurable
- existing ETS-oriented plugin behavior becomes the default `Basic` provider configuration
- built-in providers can be selected through one package-level configuration surface
- actions call the canonical facade, not implementation-specific modules

Example configuration:

```elixir
{Jido.Memory.Plugin,
 %{
   provider: {Jido.Memory.Provider.Basic,
    store: {Jido.Memory.Store.ETS, [table: :agent_memory]}}
 }}
```

Built-in Tiered provider example:

```elixir
{Jido.Memory.Plugin,
 %{
   provider: {Jido.Memory.Provider.Tiered,
    short_store: {Jido.Memory.Store.ETS, [table: :short_memory]},
    mid_store: {Jido.Memory.Store.ETS, [table: :mid_memory]},
    long_term_store: {MyApp.Memory.PostgresStore, [repo: MyApp.Repo]}}
 }}
```

Optional external provider example:

```elixir
{Jido.Memory.Plugin,
 %{
   provider: {MyApp.CustomMemoryProvider, config: %{...}}
 }}
```

## Query and Record Contract

<!-- covers: jido_memory.provider_facade.shared_record_query_contract -->

### Record

`Jido.Memory.Record` should remain canonical.

Provider-specific metadata should continue to live under `record.metadata`, using namespaced keys.
For example:

- `"tiered"`
- `"provider"`
- `"retrieval"`

This keeps the shared record envelope stable even as implementations vary.

### Query

`Jido.Memory.Query` should remain the canonical base query.

Provider-specific query features should not become mandatory core fields.
Instead, advanced implementations should use one of these paths:

- provider-specific options in `opts`
- additive `:hints` or `:extensions` fields introduced in a backward-compatible way

This matters because features like `tier_mode` are valuable but not universal.

## How Existing Libraries Map

### `jido_memory`

`jido_memory` becomes:

- the canonical contract owner
- the home of the stable plugin and actions facade
- the home of the default `Basic` provider
- the home of the built-in `Tiered` provider for the standard advanced path

The `Basic` provider can stay thin:

- use `Jido.Memory.Runtime`
- use `Jido.Memory.Store`
- return no child specs
- expose only core capabilities

The `Tiered` provider should focus on the common tiered-memory principles that belong in core:

- short, mid, and long tiers
- promotion and consolidation policy
- cross-tier retrieval
- configurable long-term persistence

<!-- covers: jido_memory.provider_migration.basic_provider_default -->
<!-- covers: jido_memory.provider_migration.built_in_advanced_providers_in_core -->

### `jido_memory_os`

`jido_memory_os` remains a standalone advanced library for users who want its native control plane and workflows, including areas such as:

- manager-driven orchestration
- journaling and replay
- governance and approvals
- framework adapters
- native plugin routes such as `pre_turn` and `post_turn`

It may add provider interop later if that becomes useful, but that interop is not the primary design center of this RFC.

<!-- covers: jido_memory.provider_architecture.provider_roles -->
<!-- covers: jido_memory.provider_migration.standalone_memory_os_boundary -->

## Composability Model

Externally, applications choose a provider bundle.
Internally, providers remain free to compose implementation-specific components.

Example internal composition for the built-in Tiered provider:

```elixir
%{
  short_store: ShortStore,
  mid_store: MidStore,
  long_term_store: LongTermStore,
  ranker: RelevanceRanker,
  lifecycle: LifecyclePolicy
}
```

This gives us modularity without requiring application authors to assemble memory systems from
a half dozen low-level parts.

## Migration Plan

### Phase 1: Introduce canonical provider behaviours in `jido_memory`

- add `Jido.Memory.Provider`
- add optional capability behaviours
- add unsupported-capability errors
- add capability discovery helpers

### Phase 2: Introduce a default `Basic` provider

- wrap current `Jido.Memory.Runtime` and `Jido.Memory.Store`
- preserve current ETS-backed behavior as the default path

### Phase 3: Make plugin and actions provider-aware

- update the plugin to accept `provider: {module, opts}`
- keep existing configuration working via compatibility defaults

### Phase 4: Add a built-in `Tiered` provider to `jido_memory`

- implement short, mid, and long tier handling in core
- add configurable long-term persistence and lifecycle policy
- expose tiered capabilities through the shared provider surface

### Phase 5: Finish docs, examples, and release hardening for built-in provider choices

- document Basic and Tiered as the standard Jido memory options
- keep `jido_memory_os` documented as a standalone advanced library
- leave optional external-provider interop as follow-on work rather than the main rollout gate

## Backward Compatibility

This RFC is intended to be additive in its first implementation stages.

<!-- covers: jido_memory.provider_migration.incremental_compatibility -->

Backward compatibility goals:

- existing `Jido.Memory.Runtime` flows continue to work
- existing ETS usage remains the default
- existing `Jido.Memory.Record` and `Jido.Memory.Store` contracts remain valid
- migration to the provider model can happen incrementally

## Alternatives Considered

### 1. Put the canonical contract in `jido_memory_os`

Rejected because `jido_memory_os` is the more opinionated implementation.
The canonical contract should not be defined by the most specialized library.

### 2. Keep the contract in `jido_memory` but make `jido_memory_os` the required advanced provider path

Rejected because it still makes the common advanced Jido memory story depend on a second library.
If `jido_memory` is the unified package, it should ship the standard provider choices itself.

### 3. Merge the full `jido_memory_os` control plane into `jido_memory`

Rejected because it would pull manager orchestration, journaling, governance, and framework-specific workflows into the core package prematurely.
The core package should absorb the common memory principles, not every advanced subsystem.

### 4. Use one giant behaviour for all features

Rejected because it would either:

- force basic providers to implement unsupported features, or
- create misleading no-op implementations

### 5. Use protocols

Rejected because provider selection is configuration-driven rather than based on the type of the first argument.

## Open Questions

- Should the built-in Tiered provider use a dedicated `LongTermStore` behaviour, or should it layer long-term persistence directly on top of `Jido.Memory.Store`?
- Should `Jido.Memory.Query` gain a backward-compatible `:hints` field, or should provider-specific options stay only in `opts`?
- Should the built-in Tiered provider expose explainable retrieval in its first version, or only lifecycle and multi-tier retrieval?
- Should external-provider interop be documented immediately, or only after the built-in provider matrix is stable?

## Recommendation

Adopt this RFC in `jido_memory` and treat `jido_memory` as the unified memory package for Jido.

That gives the ecosystem a stable center:

- one shared record and query substrate
- one stable plugin and actions facade
- one provider contract
- a built-in provider catalog for the standard memory choices
- room for optional specialized external providers

`jido_memory_os` then remains an advanced standalone system, not a required dependency for the common Jido memory path.

## References

- Memory OS of AI Agent: [https://arxiv.org/abs/2506.06326](https://arxiv.org/abs/2506.06326)
- MIRIX: [https://arxiv.org/abs/2507.07957](https://arxiv.org/abs/2507.07957)
- G-Memory: [https://arxiv.org/abs/2506.07398](https://arxiv.org/abs/2506.07398)
- Elixir Behaviours: [https://hexdocs.pm/elixir/1.5.2/behaviours.html](https://hexdocs.pm/elixir/1.5.2/behaviours.html)
- Elixir Protocols: [https://hexdocs.pm/elixir/1.18.0/protocols.html](https://hexdocs.pm/elixir/1.18.0/protocols.html)
