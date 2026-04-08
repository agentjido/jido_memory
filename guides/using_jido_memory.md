# Using Jido.Memory

This guide shows the intended application-facing usage of `jido_memory`.

## Mental Model

For application code, the canonical surface is:

- `Jido.Memory.Runtime` for reading and writing memory
- canonical structs such as `Record`, `Query`, and `RetrieveResult`
- `Jido.Memory.BasicPlugin` when integrating the built-in basic path into a `Jido.Agent`

For new code:

- use `retrieve/3` for reads
- rely on canonical structs instead of provider-specific maps

## Direct Runtime Usage

The smallest working path uses the built-in `:basic` provider with ETS.

```elixir
alias Jido.Memory.Runtime
alias Jido.Memory.RetrieveResult
alias Jido.Memory.Store.ETS

:ok = ETS.ensure_ready(table: :demo_memory)

agent = %{id: "agent-1"}

opts = [
  provider: :basic,
  provider_opts: [
    namespace: "agent:agent-1",
    store: {ETS, [table: :demo_memory]}
  ]
]

{:ok, _record} =
  Runtime.remember(agent, %{
    class: :semantic,
    kind: :fact,
    text: "The BEAM schedules lightweight processes efficiently.",
    tags: ["elixir", "beam"]
  }, opts)

{:ok, result} =
  Runtime.retrieve(agent, %{
    namespace: "agent:agent-1",
    text_contains: "beam",
    limit: 5
  }, opts)

records = RetrieveResult.records(result)
```

## Canonical Read Path

`retrieve/3` is the canonical read path.

It returns `{:ok, %Jido.Memory.RetrieveResult{}}`, which gives you:

- `hits`
- `total_count`
- `query`
- `scope`
- `provider`
- `metadata`

If you only need raw records:

```elixir
records = Jido.Memory.RetrieveResult.records(result)
```

## Canonical Write Path

`remember/3` stores one canonical memory record.

```elixir
{:ok, record} =
  Jido.Memory.Runtime.remember(agent, %{
    namespace: "agent:agent-1",
    class: :episodic,
    kind: :fact,
    text: "The user asked about provider adapters."
  })
```

Important record fields:

- `namespace`
- `class`
- `kind`
- `text`
- `content`
- `tags`
- `metadata`
- `observed_at`

## Plugin Integration

For `Jido.Agent` usage with the built-in simple memory path, attach
`Jido.Memory.BasicPlugin`.

```elixir
defmodule MyApp.Agent do
  use Jido.Agent,
    name: "memory_agent",
    default_plugins: %{__memory__: false},
    plugins: [
      {Jido.Memory.BasicPlugin,
       %{
         store: {Jido.Memory.Store.ETS, [table: :my_agent_memory]},
         namespace_mode: :per_agent,
         auto_capture: true
       }}
    ]
end
```

What the plugin gives you:

- per-agent or shared namespaces
- lightweight namespace/store state in agent state
- Jido signal routes for memory actions
- optional auto-capture of selected signals

`BasicPlugin` is intentionally not provider-generic. If another backend needs a
plugin, that package should define its own Jido integration instead of turning
core `jido_memory` into a backend adapter matrix.

## Agent Action Surface

The plugin exposes these signal routes:

- `memory.remember`
- `memory.retrieve`
- `memory.forget`

The canonical action/result pairing is:

- `memory.retrieve` returns `%{memory_result: %Jido.Memory.RetrieveResult{}}`

## Optional Capability APIs

The runtime also exposes provider-aware optional capabilities:

- `capabilities/2`
- `info/2`
- `ingest/3`
- `explain_retrieval/3`
- `consolidate/2`

Example:

```elixir
{:ok, capabilities} = Jido.Memory.Runtime.capabilities(agent, opts)
{:ok, provider_info} = Jido.Memory.Runtime.info(agent, opts)
```

## Switching Providers

Application code should stay stable when the provider changes.

Core ships the built-in `:basic` alias. External providers should register
their own atom aliases through config:

```elixir
config :jido_memory, :provider_aliases,
  mempalace: Jido.Memory.Provider.MemPalace
```

```elixir
opts = [
  provider: :mempalace,
  provider_opts: [namespace: "agent:agent-1"]
]
```

The goal is that your agent-facing code still uses:

- `Runtime.remember/3`
- `Runtime.retrieve/3`
- canonical `Record`, `Query`, and `RetrieveResult`

## When To Use Which Surface

Use `Runtime` when:

- you are writing application code
- you want the stable package-level API
- you want code to remain provider-neutral

Use the plugin when:

- you are integrating memory into a `Jido.Agent`
- you want the built-in basic provider with per-agent namespace handling
- you want memory actions and optional signal auto-capture

Use provider-specific packages directly only when:

- you need backend-native features outside the core API
- you are implementing or testing a provider package

## Related Guides

- [API Adapter Surface](./api_adapter_surface.md)
- [Basic Provider](./basic_provider.md)
- [Provider Contract](../docs/provider_contract.md)
