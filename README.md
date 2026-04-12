# Jido.Memory

`Jido.Memory` is the memory integration package for `Jido.Agent`.

The main end-user story is simple:

- attach memory to a Jido agent
- give that agent a stable way to remember and retrieve information
- keep the agent-facing experience consistent even as memory providers change

Everything else in the package exists to support that goal.

The plugin story is the center of the package. The runtime, provider contract,
and canonical structs are important, but they are plumbing for making memory
integration with Jido agents stable and predictable.

## Why This Exists

Agents usually need memory for one or more of these reasons:

- retain user preferences and facts across turns
- recall earlier context during tool use or planning
- store observations, summaries, and working notes
- expose memory lookup as an agent capability

Without a dedicated package, every agent ends up inventing its own memory
shape, storage wiring, retrieval rules, and signal/action surface.

`jido_memory` gives Jido a shared memory story:

- one built-in memory integration path for ordinary agents
- one stable canonical API for memory-aware actions and tooling
- one provider boundary for swapping memory implementations later

## What You Get

For agent builders, the package provides:

- `Jido.Memory.BasicPlugin` for the built-in memory path
- memory actions exposed on the agent
- namespace management for per-agent or shared memory
- optional signal auto-capture
- deterministic basic retrieval backed by `Jido.Memory.Store`

For provider authors and advanced integrations, the package also provides:

- `Jido.Memory.Runtime` as the stable dispatch layer
- canonical structs such as `Record`, `Query`, `Hit`, and `RetrieveResult`
- `Jido.Memory.Provider` as the provider contract
- `CapabilitySet` and `ProviderInfo` for richer provider metadata

The key distinction is:

- agents primarily interact with memory through plugins and actions
- runtime/provider/store layers exist so that plugin story can stay stable

## The Main Story: Add Memory To A Jido Agent

The built-in integration path in core is `Jido.Memory.BasicPlugin`.

`BasicPlugin` is intentionally specific to the built-in store-backed path in
core. It is not a generic adapter for every possible memory backend. That is a
feature, not a limitation: it keeps the Jido integration in core clean and easy
to understand.

`BasicPlugin` handles:

- namespace derivation
- store setup for the built-in store-backed path
- memory actions
- optional signal auto-capture

## Quick Start

### 1. Add the dependency

```elixir
defp deps do
  [
    {:jido_memory, path: "../jido_memory"}
  ]
end
```

### 2. Attach the plugin to your agent

```elixir
defmodule MyApp.SupportAgent do
  use Jido.Agent,
    name: "support_agent",
    description: "A Jido agent with built-in memory",
    default_plugins: %{__memory__: false},
    plugins: [
      {Jido.Memory.BasicPlugin,
       %{
         store: {Jido.Memory.Store.ETS, [table: :support_agent_memory]},
         namespace_mode: :per_agent,
         auto_capture: true
       }}
    ]
end
```

### 3. Make sure the ETS table exists

```elixir
alias Jido.Memory.Store.ETS

:ok = ETS.ensure_ready(table: :support_agent_memory)
```

### 4. Start your Jido runtime and agent

```elixir
{:ok, _jido} = Jido.start(name: MyApp.Jido, otp_app: :my_app)

{:ok, pid} =
  Jido.AgentServer.start_link(
    agent: MyApp.SupportAgent,
    id: "agent-1",
    jido: MyApp.Jido
  )
```

### 5. Use memory through the agent

The plugin exposes memory actions under the `memory.*` signal namespace:

- `memory.remember`
- `memory.retrieve`
- `memory.forget`

```elixir
alias Jido.Signal

{:ok, _agent} =
  Jido.AgentServer.call(
    pid,
    Signal.new!("memory.remember", %{
      class: :semantic,
      kind: :fact,
      text: "The user prefers concise answers.",
      tags: ["preferences", "user"]
    })
  )

{:ok, agent_after_retrieve} =
  Jido.AgentServer.call(
    pid,
    Signal.new!("memory.retrieve", %{
      text_contains: "concise",
      limit: 5
    })
  )
```

By default, the retrieve action returns a canonical memory result under
`memory_result`.

## What The Plugin Actually Does

`Jido.Memory.BasicPlugin` keeps the agent integration narrow and practical.

When the plugin mounts, it resolves:

- the namespace the agent should read and write under
- the store backing the built-in basic provider
- optional signal capture rules

It then keeps only lightweight plugin state in the agent:

- `namespace`
- `store`
- `auto_capture`
- `capture_signal_patterns`
- `capture_rules`

That lightweight state is enough for memory-aware actions and runtime calls to
resolve the built-in provider correctly without bloating the agent state with
backend-specific details.

## Namespace Behavior

The built-in plugin supports two namespace modes.

Per-agent namespace:

```elixir
{Jido.Memory.BasicPlugin,
 %{
   store: {Jido.Memory.Store.ETS, [table: :my_memory]},
   namespace_mode: :per_agent
 }}
```

This resolves to namespaces like:

- `agent:agent-1`
- `agent:customer-bot`

Shared namespace:

```elixir
{Jido.Memory.BasicPlugin,
 %{
   store: {Jido.Memory.Store.ETS, [table: :shared_memory]},
   namespace_mode: :shared,
   shared_namespace: "team"
 }}
```

This resolves to:

- `shared:team`

Use per-agent mode when each agent should have isolated memory. Use shared mode
when multiple agents should collaborate over the same memory pool.

## Memory Actions

Core ships three explicit actions for the built-in memory path:

- `Jido.Memory.Actions.Remember`
- `Jido.Memory.Actions.Retrieve`
- `Jido.Memory.Actions.Forget`

These are what `BasicPlugin` exposes on the agent.

Expected action behavior:

- `memory.remember` writes one record and returns `last_memory_id`
- `memory.retrieve` returns `%{memory_result: %Jido.Memory.RetrieveResult{}}`
- `memory.forget` deletes one record and returns `last_memory_deleted?`

This is the primary developer experience for agent-side memory in core.

## Custom Agent Actions

Most real agents need more than raw `remember` and `retrieve` calls. They need
domain-specific behavior built on top of memory.

That is where your own Jido actions come in.

Example:

```elixir
defmodule MyApp.Actions.RetrieveUserPreferences do
  use Jido.Action,
    name: "retrieve_user_preferences",
    description: "Retrieve preference memories for the current agent",
    schema: [
      query: [type: :string, required: true],
      limit: [type: :integer, required: false, default: 5]
    ]

  alias Jido.Memory.{RetrieveResult, Runtime}

  @impl true
  def run(params, context) do
    case Runtime.retrieve(context, %{
           kinds: [:fact],
           tags_any: ["preferences"],
           text_contains: params[:query],
           limit: params[:limit] || 5
         }) do
      {:ok, result} ->
        {:ok,
         %{
           preferences: Enum.map(RetrieveResult.records(result), & &1.text),
           memory_result: result
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

That is the intended layering:

- the plugin makes memory available to the agent
- your actions turn that memory into useful agent behavior
- the runtime is the stable plumbing underneath

## Auto-Capture

`BasicPlugin` can automatically persist selected signals as memory records.

Default capture patterns include:

- `ai.react.query`
- `ai.llm.response`
- `ai.tool.result`

This is useful when you want a memory trail of agent interactions without
writing explicit remember calls for every signal.

You can customize capture behavior:

```elixir
{Jido.Memory.BasicPlugin,
 %{
   store: {Jido.Memory.Store.ETS, [table: :captured_memory]},
   namespace_mode: :per_agent,
   capture_signal_patterns: ["ai.react.query", "bt.*"],
   capture_rules: %{
     "bt.node.enter" => %{
       class: :episodic,
       kind: :fact,
       text: "entered node",
       tags: ["bt"],
       metadata: %{phase: "entry"}
     }
   }
 }}
```

You can also disable it:

```elixir
{Jido.Memory.BasicPlugin,
 %{
   store: {Jido.Memory.Store.ETS, [table: :my_memory]},
   namespace_mode: :per_agent,
   auto_capture: false
 }}
```

Use auto-capture deliberately. It is convenient, but it also means the agent is
writing memory implicitly in response to signal traffic.

## The Built-In Memory Provider

The provider behind `BasicPlugin` is `Jido.Memory.Provider.Basic`.

`Basic` is the reference memory engine in core:

- synchronous
- deterministic
- store-backed
- simple to reason about
- good for local development, tests, and straightforward agent memory

It uses `Jido.Memory.Store` underneath, and the default practical store is ETS.

`Basic` can also use a Redis-backed store when you want durable storage without
changing the provider identity. Core now ships both `:basic` and `:redis`;
Redis can either sit underneath `:basic` as a store implementation or be chosen
explicitly as the provider.

Example:

```elixir
defmodule MyApp.MemoryRedis do
  def command(args), do: Redix.command(:memory_redis, args)
end

{Jido.Memory.BasicPlugin,
 %{
   store: {Jido.Memory.Store.Redis,
    [
      command_fn: &MyApp.MemoryRedis.command/1,
      prefix: "my_app:memory"
    ]},
   namespace_mode: :per_agent
 }}
```

The same store can be used through explicit runtime opts:

```elixir
Jido.Memory.Runtime.remember(%{id: "agent-1"}, %{
  class: :semantic,
  kind: :fact,
  text: "Persist this in Redis."
},
  provider: :basic,
  provider_opts: [
    store:
      {Jido.Memory.Store.Redis,
       [command_fn: &MyApp.MemoryRedis.command/1, prefix: "my_app:memory"]}
  ]
)
```

If you want Redis to be the explicit provider identity in core, use `:redis`:

```elixir
Jido.Memory.Runtime.remember(%{id: "agent-1"}, %{
  class: :semantic,
  kind: :fact,
  text: "Use the built-in redis provider."
},
  provider: :redis,
  provider_opts: [
    namespace: "agent:agent-1",
    command_fn: &MyApp.MemoryRedis.command/1,
    prefix: "my_app:memory"
  ]
)
```

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

What `Basic` does not try to be:

- a semantic/vector memory system
- a taxonomy engine
- a knowledge graph
- a long-term orchestration framework

Its job is to be the clean default path for Jido agents.

## Different Memory Providers

Core `jido_memory` intentionally keeps the provider story narrow.

Built into core:

- `:basic`
- `:redis`

Implemented in separate packages:

- `jido_memory_mempalace`
- `jido_memory_mem0`

That split is intentional. Different memory systems have different data models,
retrieval semantics, and infrastructure requirements. Core should not absorb all
of that complexity just to give agents a stable memory interface.

For external providers, core supports atom-based alias registration:

```elixir
config :jido_memory, :provider_aliases,
  mempalace: Jido.Memory.Provider.MemPalace,
  mem0: Jido.Memory.Provider.Mem0
```

Then application or provider-level code can select a provider explicitly:

```elixir
opts = [
  provider: :mempalace,
  provider_opts: [namespace: "agent:agent-1"]
]
```

The key point is that core agent code should not need to understand provider
internals just to work with memory.

## The Plugin Story For Other Providers

Core ships exactly one plugin story:

- `Jido.Memory.BasicPlugin`

That plugin is for the built-in store-backed path. `:redis` can be used through
runtime provider selection, while agent/plugin integrations can still configure
Redis under `BasicPlugin`.

If another provider wants deeper Jido ergonomics, that provider package should
ship its own plugin rather than expanding core into a generic backend adapter.

This keeps responsibilities clean:

- `jido_memory` owns the canonical memory surface for Jido
- `BasicPlugin` owns the simplest built-in agent integration
- advanced provider packages own advanced integration stories

## Runtime, Providers, and Stores

These layers matter, but mainly as support for the agent story.

### Runtime

`Jido.Memory.Runtime` is the stable dispatch layer used by actions, examples,
tests, and provider-aware integration code.

It exists so application code and actions do not need to call provider modules
directly.

### Providers

Providers implement the memory behavior behind the runtime.

Core contract:

- `Jido.Memory.Provider`

Optional capability behaviors:

- `Jido.Memory.Capability.Ingestion`
- `Jido.Memory.Capability.ExplainableRetrieval`
- `Jido.Memory.Capability.Lifecycle`

### Stores

Stores are low-level persistence infrastructure.

They still matter for `Basic`, but they are no longer the top-level story of
the package.

That is an important design point:

- agents think in terms of memory integration
- providers think in terms of memory behavior
- stores think in terms of persistence

## Canonical Memory Structs

Core exposes stable structs so agent tooling and provider packages can speak the
same language:

- `Jido.Memory.Record`
- `Jido.Memory.Query`
- `Jido.Memory.Scope`
- `Jido.Memory.Hit`
- `Jido.Memory.RetrieveResult`
- `Jido.Memory.Explanation`
- `Jido.Memory.IngestRequest`
- `Jido.Memory.IngestResult`
- `Jido.Memory.ConsolidationResult`
- `Jido.Memory.CapabilitySet`
- `Jido.Memory.ProviderInfo`

Two of these deserve special attention.

### CapabilitySet

`CapabilitySet` is the canonical way for a provider to describe what it
supports.

It includes:

- a canonical provider key
- flat capability atoms
- a structured capability descriptor
- provider-specific metadata

### ProviderInfo

`ProviderInfo` is the richer provider metadata surface.

It can describe:

- provider name and canonical key
- provider style or family
- structured capability metadata
- topology
- advanced provider-direct operations
- surface-boundary guidance
- resolved defaults and metadata

This belongs in core because tools and applications may want to inspect
provider metadata regardless of which provider package is installed.

## Examples

The repo includes runnable example code focused on Jido agent integration.

See:

- [examples/README.md](./examples/README.md)
- [examples/memory_agent_demo.exs](./examples/memory_agent_demo.exs)
- [examples/support/memory_agent_examples.exs](./examples/support/memory_agent_examples.exs)

The examples prove two paths:

- a plain `Jido.Agent` using `BasicPlugin`
- an AI-enabled Jido agent exposing memory retrieval as a tool

Example tests live in:

- [test/examples/memory_agent_example_test.exs](./test/examples/memory_agent_example_test.exs)

They are tagged `:examples` and are excluded from the default suite.

Run them explicitly with:

```bash
mix test --only examples
```

## Guides

For deeper documentation, start here:

- [Guides Index](./guides/index.md)
- [Using Jido.Memory](./guides/using_jido_memory.md)
- [API Adapter Surface](./guides/api_adapter_surface.md)
- [Basic Provider](./guides/basic_provider.md)
- [Provider Contract](./docs/provider_contract.md)
- [Provider-First Migration Guide](./docs/provider_migration.md)

## Summary

If you are integrating memory into a Jido agent, start with `BasicPlugin`.

That is the primary user-facing value of this package.

If you need a different memory system later, core already gives you the stable
plumbing to swap providers without throwing away your agent-facing memory story.
