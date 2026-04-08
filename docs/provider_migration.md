# Provider-First Migration Guide

This guide explains how to move from store-centric `jido_memory` usage to the
provider-first model.

## Old Mental Model

Previously, the package story was:

- `Store` is the top-level backend abstraction
- retrieval returns bare `[Record.t()]`
- plugin config is mostly store and namespace oriented

That still works for the simple ETS path, but it is no longer the whole story.

## New Mental Model

Now:

- `Jido.Memory.Runtime` is the canonical API
- `Provider` is the top-level memory-system abstraction
- `Store` remains a persistence substrate used by providers
- `retrieve/3` is the canonical read path
- `Jido.Memory.BasicPlugin` is the Jido integration for the simple built-in path

## Existing ETS Path

The default path still works and now routes through `Jido.Memory.Provider.Basic`.

```elixir
{:ok, result} =
  Jido.Memory.Runtime.retrieve(%{id: "agent-1"}, %{
    namespace: "agent:agent-1",
    text_contains: "market"
  }, store: {Jido.Memory.Store.ETS, [table: :agent_memory]})

records = Jido.Memory.RetrieveResult.records(result)
```

## Plugin Configuration

Before:

```elixir
{Jido.Memory.BasicPlugin,
 %{
   store: {Jido.Memory.Store.ETS, [table: :my_agent_memory]},
   namespace_mode: :per_agent
 }}
```

After:

```elixir
{Jido.Memory.BasicPlugin,
 %{
   store: {Jido.Memory.Store.ETS, [table: :my_agent_memory]},
   namespace_mode: :per_agent
 }}
```

## External Providers

When you add provider packages, keep agent and runtime code stable and switch
the provider. Core only ships the built-in `:basic` alias, so external provider
aliases should be registered explicitly:

```elixir
config :jido_memory, :provider_aliases,
  mempalace: Jido.Memory.Provider.MemPalace,
  mem0: Jido.Memory.Provider.Mem0
```

Then application code can select the provider:

MemPalace:

```elixir
provider: :mempalace
```

Mem0:

```elixir
provider: :mem0
```

The point of the migration is that the agent-facing contract does not need to
change when the backend does, and that the core Jido plugin story stays simple.
