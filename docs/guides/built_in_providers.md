# Built-In Providers

`jido_memory` is the unified Jido-facing memory package. It ships the common
runtime, plugin, and actions plus a small set of built-in provider choices.

## Provider Matrix

| Provider | Best For | Defaults | Advanced Features |
| --- | --- | --- | --- |
| `:basic` | Lightweight agent memory with one backing store | ETS-backed store via `Jido.Memory.Store` | Core CRUD and query only |
| `:tiered` | Standard short/mid/long memory workflows inside `jido_memory` | ETS-backed short, mid, and long-term layers | Tier-aware retrieval and lifecycle consolidation |

## Basic Provider

Use `:basic` when you want the smallest possible memory setup with a single
store and the existing compatibility surface.

```elixir
{Jido.Memory.Plugin,
 %{
   provider: :basic,
   provider_opts: [
     store: {Jido.Memory.Store.ETS, [table: :agent_memory]},
     namespace: "agent:alpha"
   ]
 }}
```

## Tiered Provider

Use `:tiered` when you want a built-in short/mid/long memory model without
bringing in `jido_memory_os`.

```elixir
{Jido.Memory.Plugin,
 %{
   provider: :tiered,
   provider_opts: [
     short_store: {Jido.Memory.Store.ETS, [table: :agent_short_memory]},
     mid_store: {Jido.Memory.Store.ETS, [table: :agent_mid_memory]},
     long_term_store:
       {Jido.Memory.LongTermStore.ETS,
        [store: {Jido.Memory.Store.ETS, [table: :agent_long_memory]}}},
     lifecycle: [
       short_to_mid_threshold: 0.65,
       mid_to_long_threshold: 0.85
     ]
   ]
 }}
```

The built-in Tiered provider always routes `:long` tier operations through
`Jido.Memory.LongTermStore`, so applications can swap the long-term backend
without rewriting the provider or agent plugin configuration.

## Tiered Explainability and Lifecycle Inspection

Tiered exposes two inspection surfaces:

- `Jido.Memory.Runtime.explain_retrieval/3` for provider-aware retrieval explanations.
- `Jido.Memory.Provider.Tiered.inspect_lifecycle/2` for provider-direct lifecycle summaries.

```elixir
provider =
  {:tiered,
   [
     short_store: {Jido.Memory.Store.ETS, [table: :agent_short_memory]},
     mid_store: {Jido.Memory.Store.ETS, [table: :agent_mid_memory]},
     long_term_store:
       {Jido.Memory.LongTermStore.ETS,
        [store: {Jido.Memory.Store.ETS, [table: :agent_long_memory]}}}
   ]}

agent = %{id: "agent-1"}

{:ok, explanation} =
  Jido.Memory.Runtime.explain_retrieval(
    agent,
    %{text_contains: "important", tiers: [:short, :mid, :long]},
    provider: provider
  )

{:ok, lifecycle_result} =
  Jido.Memory.Runtime.consolidate(agent, provider: provider, tier: :short)

{:ok, lifecycle_snapshot} =
  Jido.Memory.Provider.Tiered.inspect_lifecycle(
    agent,
    provider: provider,
    tiers: [:short, :mid, :long]
  )
```

The tradeoff is intentional:

- retrieval explanations describe why current results matched and which tiers participated
- lifecycle inspection stores only bounded last-decision metadata per record
- neither surface is meant to be a full audit trail

Open questions for later phases:

- whether Tiered should expose deeper ranking weights than the current match reasons and ordering context
- whether lifecycle inspection should ever retain more than the last known decision per record

## Custom Long-Term Persistence

Applications can provide a custom long-term backend by implementing
`Jido.Memory.LongTermStore`.

```elixir
defmodule MyApp.Memory.PostgresLongTermStore do
  @behaviour Jido.Memory.LongTermStore

  def validate_config(opts), do: if Keyword.has_key?(opts, :repo), do: :ok, else: {:error, :repo_required}
  def init(opts), do: {:ok, %{repo: Keyword.fetch!(opts, :repo)}}

  def remember(target, attrs, opts), do: {:ok, persist(target, attrs, opts)}
  def get(_target, _id, _opts), do: {:error, :not_implemented}
  def retrieve(_target, _query, _opts), do: {:ok, []}
  def forget(_target, _id, _opts), do: {:ok, false}
  def prune(_target, _opts), do: {:ok, 0}
  def info(meta, :all), do: {:ok, meta}
  def info(meta, fields) when is_list(fields), do: {:ok, Map.take(meta, fields)}
end
```

Then configure Tiered with that backend:

```elixir
provider_opts: [
  short_store: {Jido.Memory.Store.ETS, [table: :agent_short_memory]},
  mid_store: {Jido.Memory.Store.ETS, [table: :agent_mid_memory]},
  long_term_store: {MyApp.Memory.PostgresLongTermStore, [repo: MyApp.Repo]}
]
```

## Compatibility Guarantees

The built-in provider expansion keeps these existing surfaces stable:

- `Jido.Memory.Runtime` remains the public facade.
- `recall/2` remains a compatibility alias for `retrieve/3`.
- `Jido.Memory.ETSPlugin` remains available for existing ETS-backed agents.
- Runtime and action results continue to use tuple-style public results.

## When To Use `jido_memory_os`

Choose built-in `:tiered` when you want the standard tiered memory model inside
the core package.

Choose `jido_memory_os` when you need its native advanced workflows, such as:

- manager-driven orchestration
- journaling and replay
- approvals and governance
- framework-specific plugin routes

Tiered explainability and lifecycle inspection are not a replacement for
request-level journaling, replay, or manager-driven audit history. Those remain
explicitly outside the built-in provider scope.

`jido_memory_os` remains a standalone advanced library with its own facade and
plugin. It is no longer part of the release-critical built-in provider story for
`jido_memory`.

If you want to plug in another provider implementation instead of using the
built-in matrix, see [External Providers](/Users/Pascal/code/agentjido/jido_memory/docs/guides/external_providers.md).
