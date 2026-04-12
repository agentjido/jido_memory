# Basic Provider

This guide explains the built-in `Jido.Memory.Provider.Basic` implementation.

`Basic` is the reference provider for the simple `jido_memory` path. It keeps
the old ETS/store workflow intact while adapting it to the new provider-first
runtime surface.

## What It Is

`Jido.Memory.Provider.Basic` is:

- built into `jido_memory`
- synchronous
- store-backed
- provider-contract compliant
- the default provider used by `Jido.Memory.Runtime`

It is the simplest way to use the package and the reference implementation for
provider behavior in core.

## What It Uses Underneath

`Basic` uses `Jido.Memory.Store` as its persistence substrate.

That means:

- the default simple path still works
- ETS remains the default practical backend
- store adapters are still useful, but now they sit below the provider layer

## Supported Operations

`Basic` supports:

- `remember`
- `get`
- `retrieve`
- `forget`
- `prune`
- `ingest`
- `explain_retrieval`
- `consolidate`
- `capabilities`
- `info`

This makes it the most complete built-in provider in core.

## Configuration

Primary provider options:

- `namespace`
- `store`
- `store_opts`

Example:

```elixir
provider_opts = [
  namespace: "agent:agent-1",
  store: {Jido.Memory.Store.ETS, [table: :my_memory]}
]
```

The default store is ETS:

```elixir
{Jido.Memory.Store.ETS, [table: :jido_memory]}
```

Redis is also supported as a storage backend for `Basic`:

```elixir
provider_opts = [
  namespace: "agent:agent-1",
  store:
    {Jido.Memory.Store.Redis,
     [
       command_fn: &MyApp.MemoryRedis.command/1,
       prefix: "my_app:memory"
     ]}
]
```

`jido_memory` still does not take a hard Redis dependency. Your application
provides the command bridge, typically through a client such as Redix.

If you want Redis to be the explicit provider identity in core, use `provider:
:redis` instead of `:basic` with a Redis store override:

```elixir
opts = [
  provider: :redis,
  provider_opts: [
    namespace: "agent:agent-1",
    store_opts: [
      command_fn: &MyApp.MemoryRedis.command/1,
      prefix: "my_app:memory"
    ]
  ]
]
```

## Direct Runtime Usage

```elixir
alias Jido.Memory.Runtime
alias Jido.Memory.Store.ETS

:ok = ETS.ensure_ready(table: :basic_memory)

opts = [
  provider: :basic,
  provider_opts: [
    namespace: "agent:agent-1",
    store: {ETS, [table: :basic_memory]}
  ]
]

{:ok, record} =
  Runtime.remember(%{id: "agent-1"}, %{
    class: :semantic,
    kind: :fact,
    text: "Basic provider stores canonical records through Jido.Memory.Store."
  }, opts)
```

## Plugin Usage

`Jido.Memory.BasicPlugin` is the Jido integration layer for `Basic`.

```elixir
{Jido.Memory.BasicPlugin,
 %{
   store: {Jido.Memory.Store.ETS, [table: :my_agent_memory]},
   namespace_mode: :per_agent
 }}
```

The plugin keeps only namespace and store state. `Runtime` resolves those into
basic provider options when action and agent calls are dispatched.

## Retrieval Behavior

`Basic` retrieval is structured and deterministic.

It uses canonical `Query` fields such as:

- `namespace`
- `classes`
- `kinds`
- `tags_any`
- `tags_all`
- `text_contains`
- `since`
- `until`
- `limit`
- `order`

It does not do semantic/vector ranking.

That makes it useful for:

- deterministic tests
- simple agent memory
- local development
- baseline provider behavior

## Ingest, Explain, and Consolidate

### Ingest

`Basic` supports canonical ingest requests and stores each record through the
underlying store adapter.

It is useful for:

- batch inserts
- migration utilities
- importing already-normalized records

### Explain Retrieval

`Basic` can produce a simple canonical explanation describing:

- returned hit count
- match metadata
- rank and score values when present

This is not a semantic explanation system. It is a deterministic explanation of
the basic provider’s retrieval result.

### Consolidate

`Basic` consolidation maps to lifecycle cleanup of expired records.

Today this is intentionally simple:

- prune expired records
- return a canonical `ConsolidationResult`

## Option Resolution

The `Basic` provider resolves namespace and store from several places:

1. explicit runtime opts
2. attrs or query values
3. plugin state
4. provider opts
5. target-derived fallback namespace

That behavior is important because it lets the same provider work:

- directly through runtime calls
- through plugin-backed agent calls
- through action execution contexts

## When To Use Basic

Use `Basic` when you want:

- the simplest supported memory path
- deterministic behavior
- provider-contract reference behavior
- store-backed memory without backend-native complexity

Reach for external providers when you need:

- semantic/vector retrieval
- backend-native memory systems
- richer domain-specific data models

## Limitations

`Basic` is intentionally not a full advanced memory system.

It does not try to provide:

- semantic embeddings
- taxonomy layers
- knowledge graphs
- long-term orchestration
- backend-native advanced retrieval semantics

Its job is to be simple, stable, and reliable.

## Related Guides

- [Using Jido.Memory](./using_jido_memory.md)
- [API Adapter Surface](./api_adapter_surface.md)
- [Provider Contract](../docs/provider_contract.md)
