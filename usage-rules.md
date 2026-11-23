# Jido Memory usage rules

These rules apply to Jido Memory 2 on Jido v3.

## Declare and update memory

Add `Jido.Memory.Plugin` to the Agent's plugins. Declare a named collection
with a `Jido.Joi.object/1` value schema and a positive `max_entries`.

```elixir
memory do
  collection :resolutions, max_entries: 32 do
    schema Jido.Joi.object(%{summary: Jido.Joi.string()})
  end
end
```

- Return `Jido.Memory.remember/3` or `Jido.Memory.forget/2` as a Directive to
  change Agent state with the Turn. Use a nonempty UTF-8 key of at most 256 bytes.
- Call `Jido.Memory.recall/3` with the Agent or the current Action context.
  Use exact filters on declared fields. The result includes the key, value,
  and source Signal ID for each record.
- Declare an `external_collection` for live reads through a store. The host
  application owns external writes and retention. Apply scope and filters
  before the result limit.

## Use memory in reasoning

- Bind a `read` grant to the reasoning Flow with `memory FlowModule do`. The
  grant declares the collection, allowed filters, exposed fields, and limit.
- Use `RecallForModel` after `ProjectConversation`. Pass its returned context
  to `CallModel`. Set `max_evidence_bytes` to change the default of 4,096 bytes.
- Use `RecallGranted` when the Flow selects or formats evidence. It returns
  the granted fields in their original types.
- Bind external operations with `source`, `index`, or `graph`. Use `Access`
  for Action targets. Resolve Flow targets with `Jido.Memory.operation/4` and
  dispatch them with `invoke` or `handoff`.

The [examples ladder](docs/examples-ladder.md) shows these APIs in Agent
definitions and their routed Actions and Flows. See the
[upgrade guide](guides/upgrading_to_2.md) for the Jido Memory 1.x boundary.
