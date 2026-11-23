# Upgrade to Jido Memory 2

Jido Memory 2.0.0 is the proposed major release for Jido v3. The package
currently builds against Jido `3.0.0-beta.3`. Upgrade Jido before you change
an Agent or library to Jido Memory 2.

## State-backed collections

Use `Jido.Memory.Plugin` to declare a `collection` with a Joi value schema and
`max_entries`. Return `Jido.Memory.remember/3` or `forget/2` as a Directive. The
Agent applies the Directive with its Turn. Call `Jido.Memory.recall/3` with the
Agent or the Action context.

## External collections

Use a separate declaration to read records from a store during a live Turn.

```elixir
memory do
  external_collection :resolutions,
    store: {Jido.Memory.Store.ETS, %{name: MyApp.Resolutions, scope: "support"}} do
    schema(Jido.Joi.object(%{summary: Jido.Joi.string()}))
  end
end
```

The host owns external mutations, retention, and retry. The `:limit` option
bounds recall results. `max_entries` applies only to state-backed
collections. The Ecto example shows host-owned writes and operation receipts.

The Ash store binding declares `:filter_fields`. Its generated query Action
receives `:collection`, `:where`, and `:limit`. The Action must apply both
filters in the authorized scope before it applies the limit.

An ETS read timeout returns `:store_timeout`. A timed-out write returns
`:write_outcome_unknown`. Check the store or use an idempotent host operation
before you retry the write.

## Flow composition

Use `step` with a fixed Action or Flow module. Use `invoke` when a Flow must
choose a target at runtime. An expander can call `Jido.Memory.operation/4` to
resolve a named binding and return `{:continue, input, target}`. Jido runs an
invoked Flow as a child of the calling Flow. A Flow with waits must run as a
root Flow on a durable host. Resolve that target in a terminal `handoff`
selector and return `{:handoff, input, target}`. `Jido.Memory.access/5`
calls Action targets immediately.

## Keep legacy providers on Jido Memory 1

The 2.0.0 API replaces the 1.x provider API. Keep legacy Agent checkpoints and
store data under 1.x until you have a migration for their schemas and IDs.
The sibling Mem0 and MemPalace packages pin Hex `1.0.1`. KG pins the immutable
`aa6a42b14e7b80d9635e153a2d6e4413a1f2ea78` revision from its prior lock.
Keep these pins when the new API lands on `main`.
