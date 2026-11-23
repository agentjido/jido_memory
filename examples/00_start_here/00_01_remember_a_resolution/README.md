# 00_01 Remember a resolution

A support Agent records the resolution of a ticket and can recall it by issue
on a later Turn.

## What you will learn

- Declare a bounded memory collection with a `Jido.Joi` schema.
- Return a memory Directive from an Action and recall the record from the
  resulting Agent.

## Read the code

Read the collection in the shared [support Agent](../../support/resolution_agent.exs)
first, then follow the `examples.memory.ticket.resolved` route. The Action
builds a write Directive. The memory Plugin applies it during the Turn.

```elixir
defmodule SupportDesk do
  use Jido.Agent, name: "support_desk", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}

  memory do
    collection :resolutions, max_entries: 3 do
      schema Joi.object(%{issue: Joi.string(), summary: Joi.string()})
    end
  end

  routes do
    signal_source "/examples/memory/remember-resolution"

    route "examples.memory.ticket.resolved", as: :resolve do
      action %{key: key, value: value},
        schema: Joi.object(%{key: Joi.string(), value: Joi.map()}),
        context: context do
        {:ok, context.agent_state, [Memory.remember(:resolutions, key, value)]}
      end
    end
  end
end

agent = SupportDesk.instantiate!(id: "support-desk")
value = %{issue: "duplicate_charge", summary: "Refunded the second charge"}
signal = SupportDesk.resolve_signal!(%{key: "T-17", value: value})
source_id = signal.id

{:ok, next_agent, [_write]} = SupportDesk.cmd(agent, signal)

{:ok, [%{key: "T-17", value: ^value, source_signal_id: ^source_id}]} =
  Jido.Memory.recall(next_agent, :resolutions, where: %{issue: "duplicate_charge"}, limit: 1)
```

## Run it

From the package root, run the example.

```sh
mix run examples/00_start_here/00_01_remember_a_resolution/run.exs
```

The script checks that recall returns one record for `T-17` with its resolution
and the original Signal ID. It then prints the record.

To run the Agent-state contract tests, use this command.

```sh
mix test test/jido_memory/agent_state_test.exs --warnings-as-errors
```

## Important behavior

Use `next_agent` for recall. `cmd/3` returns a new Agent value. A resolution
with an invalid value, such as an integer summary, fails the Turn. The previous
Agent value still contains its last valid record.

Writing the same key replaces its value and makes it the newest record. A write
to a new key in a full collection evicts the least recently written record.

## Limits

This example uses Agent state and pure Turns. The Agent state lasts as long as
the returned value or a saved checkpoint. Recall uses exact field matches.

## Files

- [Runnable example](run.exs)
- [Memory API](../../../lib/jido_memory.ex)
- [Memory Plugin](../../../lib/jido_memory/plugin.ex)
- [Agent-state contract tests](../../../test/jido_memory/agent_state_test.exs)
