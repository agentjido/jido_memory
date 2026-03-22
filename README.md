# Jido.Memory

`Jido.Memory` is the unified, provider-backed memory package for Jido agents.

<!-- covers: jido_memory.package.structured_memory_contract jido_memory.package.default_ets_path jido_memory.package.plugin_and_actions jido_memory.package.auto_capture -->

Version 1 provides:
- Structured records (`Jido.Memory.Record`)
- Structured query filters (`Jido.Memory.Query`)
- A canonical provider contract (`Jido.Memory.Provider`)
- Built-in providers (`Jido.Memory.Provider.Basic`, `Jido.Memory.Provider.Tiered`, and `Jido.Memory.Provider.Mirix`)
- A long-term persistence behavior (`Jido.Memory.LongTermStore`)
- A provider-aware plugin (`Jido.Memory.Plugin`)
- A compatibility Jido plugin (`Jido.Memory.ETSPlugin`)
- Explicit actions (`memory.remember`, `memory.retrieve`, `memory.recall`, `memory.forget`)
- Auto-capture hooks for AI and non-LLM signal flows

## Canonical Providers

`jido_memory` separates the stable memory facade from the implementation behind it.

- `Jido.Memory.Runtime` stays the public API.
- `Jido.Memory.Provider.Basic` is the default provider for store-backed memory.
- `Jido.Memory.Provider.Tiered` is the built-in short/mid/long provider for standard advanced memory flows.
- `Jido.Memory.Provider.Mirix` is the built-in routed memory-type provider for typed retrieval, provider-direct ingestion, and protected vault workflows.
- `Jido.Memory.Plugin` is the common provider-aware plugin for core memory flows.
- `Jido.Memory.ETSPlugin` remains the compatibility wrapper for existing ETS-backed agents.

That lets the same core plugin and runtime calls target any built-in provider without changing agent code.

## Built-In Provider Choices

| Provider | Choose It When | Notes |
| --- | --- | --- |
| `:basic` | You want the smallest possible setup with one backing store | Default provider, keeps existing ETS-style usage simple |
| `:tiered` | You want short/mid/long memory and built-in promotion | Ships in `jido_memory` and uses `Jido.Memory.LongTermStore` for long-term persistence |
| `:mirix` | You want routed memory types, active retrieval traces, and provider-direct ingestion or vault workflows | Ships in `jido_memory`; keeps common runtime/plugin flows for retrieval while leaving ingest and protected memory explicit |

## Adoption Paths

The supported adoption story is incremental:

1. stay on built-in `:basic` if you only need the original store-backed path
2. move to built-in `:tiered` when you want explainable short/mid/long memory inside `jido_memory`
3. move to built-in `:mirix` when you want typed routed retrieval plus explicit provider-direct ingestion and protected memory
4. switch the Tiered long-term backend from ETS to Postgres when long-tier durability matters
5. adopt an external provider only when the built-in paths no longer fit your architecture
6. adopt `jido_memory_os` when you need manager-driven workflows that are intentionally outside the built-in package scope

The release-gated support matrix is documented in
[Follow-On Acceptance Matrix](/Users/Pascal/code/agentjido/jido_memory/docs/guides/follow_on_acceptance_matrix.md).

## Installation

Add dependencies in `mix.exs`:

```elixir
defp deps do
  [
    {:jido_memory, "~> 0.1"},
    {:jido, "~> 2.1"},
    {:jido_action, "~> 2.1"},
    {:jido_ai, "~> 2.0"}
  ]
end
```

## Use As A Jido Plugin

### Basic Provider Example

Use `Jido.Memory.Plugin` when you want the common agent-facing memory API with a single store-backed provider:

```elixir
defmodule MyApp.Agent do
  use Jido.Agent,
    name: "my_agent",
    default_plugins: %{__memory__: false},
    plugins: [
      {Jido.Memory.Plugin,
       %{
         provider: :basic,
         provider_opts: [
           store: {Jido.Memory.Store.ETS, [table: :my_agent_memory]},
           namespace: "agent:my_agent"
         ]
       }}
    ]
end
```

### Tiered Provider Example

The same plugin surface can switch to built-in tiered memory by changing only the provider config:

```elixir
defmodule MyApp.Agent do
  use Jido.Agent,
    name: "my_agent",
    default_plugins: %{__memory__: false},
    plugins: [
      {Jido.Memory.Plugin,
       %{
         provider: :tiered,
         provider_opts: [
           short_store: {Jido.Memory.Store.ETS, [table: :my_agent_short_memory]},
           mid_store: {Jido.Memory.Store.ETS, [table: :my_agent_mid_memory]},
           long_term_store:
             {Jido.Memory.LongTermStore.ETS,
              [store: {Jido.Memory.Store.ETS, [table: :my_agent_long_memory]}}},
           lifecycle: [
             short_to_mid_threshold: 0.65,
             mid_to_long_threshold: 0.85
           ]
         ]
       }}
    ]
end
```

### MIRIX Provider Example

Use `:mirix` when you want common plugin/runtime flows for routed retrieval and
provider-direct APIs for ingestion or protected vault memory:

```elixir
defmodule MyApp.Agent do
  use Jido.Agent,
    name: "my_agent",
    default_plugins: %{__memory__: false},
    plugins: [
      {Jido.Memory.Plugin,
       %{
         provider: :mirix,
         provider_opts: [
           core_store: {Jido.Memory.Store.ETS, [table: :my_agent_core_memory]},
           episodic_store: {Jido.Memory.Store.ETS, [table: :my_agent_episodic_memory]},
           semantic_store: {Jido.Memory.Store.ETS, [table: :my_agent_semantic_memory]},
           procedural_store: {Jido.Memory.Store.ETS, [table: :my_agent_procedural_memory]},
           resource_store: {Jido.Memory.Store.ETS, [table: :my_agent_resource_memory]},
           vault_store: {Jido.Memory.Store.ETS, [table: :my_agent_vault_memory]},
           retrieval: [planner_mode: :broad]
         ]
       }}
    ]
end
```

### Compatibility ETS Plugin

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

### Basic Runtime Example

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
  Jido.Memory.Runtime.retrieve(%{id: "agent-1"}, %{
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

### Tiered Runtime Example

```elixir
provider =
  {:tiered,
   [
     short_store: {Jido.Memory.Store.ETS, [table: :short_memory]},
     mid_store: {Jido.Memory.Store.ETS, [table: :mid_memory]},
     long_term_store:
       {Jido.Memory.LongTermStore.ETS,
        [store: {Jido.Memory.Store.ETS, [table: :long_memory]}}}
   ]}

agent = %{id: "agent-1"}

{:ok, record} =
  Jido.Memory.Runtime.remember(agent, %{
    class: :semantic,
    kind: :fact,
    text: "Important memories can be promoted.",
    importance: 1.0
  }, provider: provider)

{:ok, %{promoted_to_mid: 1}} =
  Jido.Memory.Runtime.consolidate(agent, provider: provider, tier: :short)

{:ok, promoted_record} =
  Jido.Memory.Runtime.get(agent, record.id, provider: provider, tier: :mid)

{:ok, explanation} =
  Jido.Memory.Runtime.explain_retrieval(
    agent,
    %{text_contains: "Important memories", tiers: [:short, :mid, :long]},
    provider: provider
  )

{:ok, lifecycle_snapshot} =
  Jido.Memory.Provider.Tiered.inspect_lifecycle(
    agent,
    provider: provider,
    tiers: [:short, :mid, :long]
  )
```

`Runtime.explain_retrieval/3` is the common provider-aware entrypoint for why a
result matched. `Jido.Memory.Provider.Tiered.inspect_lifecycle/2` is
provider-direct and reports bounded promotion and skip metadata for the last
known lifecycle decision on each tracked record.

### MIRIX Runtime and Provider-Direct Example

```elixir
provider =
  {:mirix,
   [
     core_store: {Jido.Memory.Store.ETS, [table: :core_memory]},
     episodic_store: {Jido.Memory.Store.ETS, [table: :episodic_memory]},
     semantic_store: {Jido.Memory.Store.ETS, [table: :semantic_memory]},
     procedural_store: {Jido.Memory.Store.ETS, [table: :procedural_memory]},
     resource_store: {Jido.Memory.Store.ETS, [table: :resource_memory]},
     vault_store: {Jido.Memory.Store.ETS, [table: :vault_memory]}
   ]}

agent = %{id: "agent-1"}

{:ok, ingest_result} =
  Jido.Memory.Provider.Mirix.ingest(
    agent,
    %{
      entries: [
        %{modality: :document, content: "Deployment runbook"},
        %{modality: :workflow, content: "workflow for release readiness"}
      ]
    },
    provider: provider
  )

{:ok, records} =
  Jido.Memory.Runtime.retrieve(
    agent,
    %{
      text_contains: "workflow",
      query_extensions: %{mirix: %{planner_mode: :focused}}
    },
    provider: provider
  )

{:ok, explanation} =
  Jido.Memory.Runtime.explain_retrieval(
    agent,
    %{
      text_contains: "workflow",
      query_extensions: %{mirix: %{planner_mode: :focused}}
    },
    provider: provider
  )

{:ok, vault_record} =
  Jido.Memory.Provider.Mirix.put_vault_entry(
    agent,
    %{kind: :credential, text: "secret-token"},
    provider: provider
  )
```

For MIRIX, the shared runtime remains intentionally selective:

- `remember/3`, `retrieve/3`, and `explain_retrieval/3` stay on the common provider-aware surface
- multimodal or batch ingest stays provider-direct through `Jido.Memory.Provider.Mirix.ingest/3`
- protected memory stays provider-direct through `put_vault_entry/3`, `get_vault_entry/3`, and `forget_vault_entry/3`

## Memory Actions

The plugin exposes these signal routes:
- `memory.remember` -> `Jido.Memory.Actions.Remember`
- `memory.retrieve` -> `Jido.Memory.Actions.Retrieve`
- `memory.recall` -> `Jido.Memory.Actions.Recall`
- `memory.forget` -> `Jido.Memory.Actions.Forget`

Action result conventions:
- `Remember` -> `%{last_memory_id: id}`
- `Retrieve` -> `%{memory_results: [...]}` (or custom `memory_result_key`)
- `Recall` -> `%{memory_results: [...]}` (or custom `memory_result_key`)
- `Forget` -> `%{last_memory_deleted?: boolean}`

## Long-Term Persistence

The built-in Tiered provider always routes `:long` tier operations through `Jido.Memory.LongTermStore`.
The default long-term backend is `Jido.Memory.LongTermStore.ETS`, and the first
supported durable backend is `Jido.Memory.LongTermStore.Postgres`. Applications
can still swap in custom backends by implementing the behavior.

```elixir
provider_opts = [
  short_store: {Jido.Memory.Store.ETS, [table: :short_memory]},
  mid_store: {Jido.Memory.Store.ETS, [table: :mid_memory]},
  long_term_store: {MyApp.Memory.PostgresLongTermStore, [repo: MyApp.Repo]}
]
```

## External Provider Interop

External providers are now an opt-in path on top of the same common runtime and
plugin surface.

- Direct modules and `{module, opts}` tuples work without registration.
- Alias-based selection is helper-only through `provider_aliases`.
- Provider-owned runtime processes stay caller-owned through `Jido.Memory.ProviderBootstrap`.

```elixir
aliases = %{external_demo: MyApp.Memory.ExternalProvider}

{Jido.Memory.Plugin,
 %{
   provider: :external_demo,
   provider_aliases: aliases,
   provider_opts: [store: {Jido.Memory.Store.ETS, [table: :external_memory]}]
 }}
```

Guide:
- `/Users/Pascal/code/agentjido/jido_memory/docs/guides/external_providers.md`

## Compatibility Guarantees

The built-in provider expansion keeps the existing public contract stable:

- `Jido.Memory.Runtime` remains the main facade
- `recall/2` remains supported as a compatibility alias to `retrieve/3`
- `Jido.Memory.ETSPlugin` remains available for existing ETS-backed agents
- public runtime and action results stay tuple-based

## Relationship To `jido_memory_os`

`jido_memory` now ships the standard built-in provider choices for Jido memory context management.

`jido_memory_os` remains a standalone advanced library with its own native facade and plugin. Reach for it when you need features outside the built-in provider scope, such as:

- manager-driven orchestration
- journaling and replay
- approvals and governance
- framework-specific plugin flows

The built-in Tiered provider does not try to replace request-level journaling,
replay, or manager-driven audit history. Its explainability and lifecycle
inspection surfaces are intentionally lighter-weight.

The built-in release story for `jido_memory` is now `:basic`, `:tiered`, and `:mirix`.
External-provider interop is available as an opt-in seam, but it does not
change the built-in defaults or make `jido_memory_os` a required dependency.

## Known Limits

- external providers are only required to satisfy the core provider contract unless they explicitly implement optional capabilities
- Tiered explainability is intentionally bounded and is not a substitute for journaling or replay
- the built-in Postgres long-term backend currently evaluates the overlapping structured query subset in Elixir after a namespace-scoped fetch
- Redis is not yet a first-party durable long-term backend

## Examples

- `/Users/Pascal/code/agentjido/jido_memory/examples/basic_provider_agent.exs`
- `/Users/Pascal/code/agentjido/jido_memory/examples/tiered_provider_agent.exs`
- `/Users/Pascal/code/agentjido/jido_memory/examples/mirix_provider_agent.exs`
- `/Users/Pascal/code/agentjido/jido_memory/examples/postgres_tiered_agent.exs`
- `/Users/Pascal/code/agentjido/jido_memory/examples/external_provider_agent.exs`

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
For durable storage, implement another `Jido.Memory.Store` adapter or a custom `Jido.Memory.LongTermStore` backend for the Tiered provider.
