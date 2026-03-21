# Jido.Memory

`Jido.Memory` is a basic, data-driven memory system for Jido agents.

<!-- covers: jido_memory.package.structured_memory_contract jido_memory.package.default_ets_path jido_memory.package.plugin_and_actions jido_memory.package.auto_capture -->

Version 1 uses ETS as the authoritative store and provides:
- Structured records (`Jido.Memory.Record`)
- Structured query filters (`Jido.Memory.Query`)
- A Jido plugin (`Jido.Memory.ETSPlugin`)
- Explicit actions (`memory.remember`, `memory.recall`, `memory.forget`)
- Auto-capture hooks for AI and non-LLM signal flows

## Installation

Add dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:jido, "~> 2.1"},
    {:jido_action, "~> 2.1"},
    {:jido_ai, "~> 2.0"}
  ]
end
```

## Use As A Jido Plugin

Jido includes a default memory plugin at `:__memory__`, so replace it explicitly:

```elixir
defmodule MyApp.Agent do
  use Jido.Agent,
    name: "my_agent",
    default_plugins: %{__memory__: false},
    plugins: [
      {Jido.Memory.ETSPlugin,
       %{
         store: {Jido.Memory.Store.ETS, [table: :my_agent_memory]},
         namespace_mode: :per_agent,
         auto_capture: true,
         capture_signal_patterns: ["ai.react.query", "ai.llm.response", "ai.tool.result"]
       }}
    ]
end
```

### Shared Namespace Mode

```elixir
{Jido.Memory.ETSPlugin,
 %{
   store: {Jido.Memory.Store.ETS, [table: :shared_memory]},
   namespace_mode: :shared,
   shared_namespace: "strategy-team"
 }}
```

## Jido.AI Agent Example

```elixir
defmodule MyApp.ReActAgent do
  use Jido.AI.Agent,
    name: "react_memory_agent",
    tools: [MyApp.Tools.Search],
    default_plugins: %{__memory__: false},
    plugins: [
      {Jido.Memory.ETSPlugin,
       %{
         store: {Jido.Memory.Store.ETS, [table: :react_memory]},
         namespace_mode: :per_agent,
         auto_capture: true
       }}
    ]
end
```

Auto-captured events include:
- `ai.react.query` -> `class: :episodic`, `kind: :user_query`
- `ai.llm.response` -> `class: :episodic`, `kind: :assistant_response`
- `ai.tool.result` -> `class: :episodic`, `kind: :tool_result`

## Non-LLM / Behavior-Tree Style Example

```elixir
# Configure capture for behavior-tree signals
{Jido.Memory.ETSPlugin,
 %{
   store: {Jido.Memory.Store.ETS, [table: :bt_memory]},
   capture_signal_patterns: ["bt.*", "strategy.*"]
 }}
```

Signals matching `bt.*` are captured as generic memory events by default:
- `class: :working`
- `kind: :signal_event`

You can still write/read memory explicitly through actions or API calls.

## Explicit API

```elixir
# Write
{:ok, record} =
  Jido.Memory.Runtime.remember(%{id: "agent-1"}, %{
    class: :semantic,
    kind: :fact,
    text: "Market opened at 09:30",
    tags: ["market", "session"]
  }, store: {Jido.Memory.Store.ETS, [table: :my_memory]})

# Read one
{:ok, same_record} =
  Jido.Memory.Runtime.get(%{id: "agent-1"}, record.id, store: {Jido.Memory.Store.ETS, [table: :my_memory]})

# Query
{:ok, results} =
  Jido.Memory.Runtime.recall(%{id: "agent-1"}, %{
    classes: [:semantic],
    tags_any: ["market"],
    limit: 10,
    order: :desc,
    store: {Jido.Memory.Store.ETS, [table: :my_memory]}
  })

# Delete
{:ok, deleted?} =
  Jido.Memory.Runtime.forget(%{id: "agent-1"}, record.id, store: {Jido.Memory.Store.ETS, [table: :my_memory]})
```

## Memory Actions

The plugin exposes these signal routes:
- `memory.remember` -> `Jido.Memory.Actions.Remember`
- `memory.recall` -> `Jido.Memory.Actions.Recall`
- `memory.forget` -> `Jido.Memory.Actions.Forget`

Action result conventions:
- `Remember` -> `%{last_memory_id: id}`
- `Recall` -> `%{memory_results: [...]}` (or custom `memory_result_key`)
- `Forget` -> `%{last_memory_deleted?: boolean}`

## Record Model

`Jido.Memory.Record` fields:
- `id`, `namespace`, `class`, `kind`, `text`, `content`, `tags`, `source`
- `observed_at`, `expires_at`
- `embedding` (stored only; no vector search in v1)
- `metadata`, `version`

Canonical `class` values:
- `:episodic`
- `:semantic`
- `:procedural`
- `:working`

`kind` remains open (`atom` or `string`) for domain-specific memory shapes.

## RAG Roadmap Compatibility

v1 is intentionally not a vector retrieval system.

It is RAG-ready by schema:
- `embedding` field exists on records
- store behavior (`Jido.Memory.Store`) is adapter-based

You can introduce advanced backends later without changing the high-level API.

## ETS Durability Note

ETS is in-memory only. Memory records are lost on node restart.
For durable storage, implement another `Jido.Memory.Store` adapter.
