# Jido v3 agent memory DSL

Status: design draft. See the [upgrade guide](../../guides/upgrading_to_2.md)
for the current package contract.

Declare what an agent can remember in a `memory` block. A collection groups
records with the same schema and selects a scope and a store. A record has a
key, a value, and a source reference. Actions and Flows decide when to remember,
recall, and forget. Capture, search pipelines, and graphs can build on these
operations.

## Declare and write memory

```elixir
defmodule Support.Agent do
  use Jido.Agent, name: "support", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}

  memory do
    collection :resolutions, max_entries: 32 do
      schema Joi.object(%{
        issue: Joi.string() |> Joi.max(80),
        summary: Joi.string() |> Joi.max(500)
      })
    end
  end

  routes do
    signal_source "/support"

    route "ticket.resolved", as: :resolved do
      action %{ticket_id: id, issue: issue, summary: summary},
        schema: Joi.object(%{
          ticket_id: Joi.string(),
          issue: Joi.string(),
          summary: Joi.string()
        }),
        context: context do
        resolution = Memory.remember(:resolutions, id, %{issue: issue, summary: summary})
        {:ok, context.agent_state, [resolution]}
      end
    end
  end
end
```

`remember/3` builds a Directive. The memory plugin validates the key and value
and applies the write during reduction. Keys are nonempty strings of at most
256 bytes. A write to an existing key replaces the value and makes it the
newest record in the collection. When the collection reaches its limit, the
next write to a new key evicts the least recently written record. The plugin
records the source Signal ID with each write.
`Memory.forget(:resolutions, id)` builds a Directive that deletes the key. A
delete for an absent key succeeds.

The default store is Agent state and the default scope is the Agent instance.
A ticket ID identifies one record within one collection on that Agent. Reuse a
long-lived support Agent if it must recall resolutions across tickets. A new
Agent instance starts with empty state-backed collections.

## Recall memory

```elixir
alias Jido.Memory

agent = Support.Agent.instantiate!(id: "support-desk")

signal = Support.Agent.resolved_signal!(%{
  ticket_id: "T-17",
  issue: "duplicate_charge",
  summary: "Refunded the second charge."
})

{:ok, agent, [_directive]} = Support.Agent.cmd(agent, signal)

{:ok, [%{key: "T-17", value: %{summary: "Refunded the second charge."}}]} =
  Memory.recall(agent, :resolutions, where: %{issue: "duplicate_charge"}, limit: 3)
```

An Action can pass its `context` as the first argument to `recall/3`. It reads
the Agent state at the start of the Turn. A subsequent Turn can read the
committed write. Filters match declared fields by equality. Results contain
the key, value, and source Signal ID, newest write first. An empty result
returns `{:ok, []}`. An unknown collection, invalid filter, or invalid limit
returns an error.

## Give a reasoning Flow access to memory

```elixir
memory Support.AnswerFlow do
  collection :resolutions, max_entries: 32 do
    schema Joi.object(%{issue: Joi.string(), summary: Joi.string()})
  end

  read :prior_resolutions,
    collection: :resolutions,
    filters: [:issue],
    expose: [:summary],
    limit: 1
end
```

In `Support.AnswerFlow`, place `Jido.Memory.Actions.RecallForModel` after
`ProjectConversation`. Pass the open model context, the grant name, and
`where: %{issue: "duplicate_charge"}`. Pass the returned context to
`CallModel`. The model receives the key and approved summary. The recall
trace includes the grant decision and source Signal ID. The Agent makes the
grant available when the bound Flow is the sole matching root route.

Session transcripts can stay in `Jido.Session` and `Jido.Thread`. The memory
collection holds the selected records the Agent can recall later. See the
[runnable Answer from memory example](../../examples/00_start_here/00_02_answer_from_memory/README.md).

## Bind a source, index, or graph

Declare a name and the operations the Agent can call. Each operation names
a Jido Action or Flow. The Agent can use these declarations with or without
collections. A name is unique within its own kind.

```elixir
memory do
  source :guide_repository, operations: [fetch: SupportDesk.FetchDocument]

  index :guides,
    operations: [
      put: SupportDesk.IndexDocument,
      status: SupportDesk.IndexStatus,
      search: SupportDesk.SearchGuides
    ]

  graph :guide_links, operations: [search: SupportDesk.SearchGuideLinks]
end
```

From an Action, pass the current Turn context and the target's input map.

```elixir
Memory.access(context, :index, :guides, :search, %{
  package: "jido",
  version: "3.0.0-beta.3",
  question: "How do I declare Agent state?"
})
```

In a Flow, use `Jido.Memory.Actions.Access` for a step that forwards the
complete result. Use `Memory.access/5` in an inline step when the Flow must
process the result or provide its own output schema.

Bindings are available to Actions and Flows on the Agent's Turns. The target
validates inputs, applies tenant and actor policy, and uses connections from
the trusted runtime context. The binding selects the operation. The reasoning
Flow checks the result before it supplies excerpts to the model. An operation
that writes to a backend runs during the Turn. Its target owns transaction
and retry behavior for that backend. Use `read` to grant model access to a
typed collection.

See the [exact-release Arcana Agent](../../examples/04_find_evidence/04_03_answer_for_an_exact_release/run.exs)
and [AshJido article Agent](../../examples/05_govern_learning/05_05_index_ash_articles/run.exs)
for complete examples.

## Store bindings

```elixir
memory do
  store :history, {Jido.Memory.Store.Ecto, repo: Support.Repo}

  store :ash_preferences,
    {Jido.Memory.Store.Ash,
     actions: [
       put: Support.Accounts.Jido.RememberPreference,
       get: Support.Accounts.Jido.GetPreference,
       query: Support.Accounts.Jido.ListPreferences,
       delete: Support.Accounts.Jido.ForgetPreference
     ]}

  collection :resolutions, store: :history, scope: Support.Access.Customer do
    schema Support.Memory.Resolution
  end

  collection :preferences, store: :ash_preferences, scope: Support.Access.Customer do
    schema Support.Memory.Preference
  end
end
```

An external adapter works with scoped record keys and bounded queries. Its
contract is `put`, `get`, `query`, and `delete`. Reads support exact filters,
stable ordering, and a limit. A successful `put` replaces a value at the
same scoped key. A successful `delete` leaves the key absent. Each application
controls scope resolution through trusted runtime context. A scoped identity
includes the collection and key within that scope.

The first adapter targets are Agent state, ETS, Ecto, and AshJido. Agent state
fits bounded per-Agent memory. ETS gives tests and local use a process-independent
store within one BEAM instance. Ecto uses the host Repo and an indexed memory
table. The first Ecto targets are PostgreSQL and SQLite for the common query
contract. The host owns migrations. The existing v2 PostgreSQL store uses an
Ecto Repo and PostgreSQL-specific SQL. The v2 package also has a Redis store.

The Ash adapter is optional. It calls explicitly bound AshJido Actions backed
by an application-owned Resource. The application supplies trusted actor and
tenant context. Ash controls authorization, identities, and the data layer.
When an application selects the Ash adapter, configuration must validate the
compatible AshJido installation and the required Action bindings. The Resource
owns the atomic upsert for its scoped identity.

`Jido.Persistence.Ecto` and `AshJido.Persistence.Adapter` can store the Agent
checkpoint, including state-backed memory. External memory stores hold records
that Actions can query by scope, collection, and field. Applications can use the
same database for the two layers.

## Turn behavior

- The `memory` block registers one plugin and passes it the collection
  definitions as static options. Compilation reports duplicate collection
  names, invalid limits, and Joi schemas that are invalid for stored state.
- The plugin owns one `:memory` state field. `directives/1` claims `Remember`
  and `Forget`. For state-backed collections, `reduce/2` applies them in batch
  order and checks collection, key, and schema. An invalid write fails the Turn.
  Reads in `Jido.Agent.cmd/3` use the state at the start of the Turn.
- Records use portable values. Jido saves them with Agent state in a persistent
  instance and loads them on restore. A live Agent without persistence keeps
  state-backed records for its lifetime.
- For an external store, the Turn validates and records the write intent.
  A live runtime applies it after commit. The application can rely on a record
  only when the adapter confirms the write. Durable delivery requires a pending
  request in the checkpoint and an idempotent retry strategy.
- The first test sends a series of resolution Signals to check writes, recall,
  eviction, and restore. A second test sends a write with invalid data and
  checks that both memory and the rest of Agent state retain their prior values.

## Design questions after the first slice

- **Capture rules.** If several routes need the same capture policy, a rule
  should name the domain event and the code that selects the fields. A rule
  should have the same commit behavior as `remember/3`.
- **Indexes.** Lexical, vector, and graph search can provide candidates for
  recall. Each result should refer to a scoped record that the reader can open.

The first slice uses Jido's module-level plugin registration, custom Directives,
and plugin state. See [Behavior Tree DSL](https://github.com/agentjido/jido/blob/bb8363bac8725022e065b7e91d19e023c93ff5b8/lib/jido/behavior_tree/dsl.ex),
[Custom Directives](https://github.com/agentjido/jido/blob/bb8363bac8725022e065b7e91d19e023c93ff5b8/guides/plugins/plugin-custom-directives.livemd),
and [Plugin Persistence](https://github.com/agentjido/jido/blob/bb8363bac8725022e065b7e91d19e023c93ff5b8/guides/plugins/plugin-persistence.md).
