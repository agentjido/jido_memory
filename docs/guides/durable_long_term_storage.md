# Durable Long-Term Storage

`Jido.Memory.Provider.Tiered` keeps short and mid memory local by default and
routes the `:long` tier through `Jido.Memory.LongTermStore`.

Phase 3 adds the first supported durable backend for that seam:
`Jido.Memory.LongTermStore.Postgres`.

## Why Postgres First

Postgres is the first supported durable backend because it fits the current
contract better than Redis:

- stronger persistence guarantees without depending on separate snapshot or AOF choices
- better long-term operational story for durable agent memory
- clearer room for indexing and backend-native query pushdown later

Redis remains follow-on work. It is not currently a first-party durable backend.

## Host App Dependencies

If you want to use the built-in Postgres backend, include `:postgrex` in the
host application dependency set:

```elixir
defp deps do
  [
    {:jido_memory, "~> 0.1"},
    {:postgrex, "~> 0.22"}
  ]
end
```

## Basic Tiered Configuration

```elixir
provider =
  {:tiered,
   [
     short_store: {Jido.Memory.Store.ETS, [table: :agent_short_memory]},
     mid_store: {Jido.Memory.Store.ETS, [table: :agent_mid_memory]},
     long_term_store:
       {Jido.Memory.LongTermStore.Postgres,
        [
          database: "postgres",
          username: "my_app",
          socket_dir: "/tmp",
          table: "agent_long_memory"
        ]}
   ]}
```

The built-in Postgres backend validates and creates its table on initialization.

## Migration From ETS Long-Term Storage

There is no built-in dual-write or journal replay path in `jido_memory`.
Migration from ETS long-term storage to Postgres is application-managed.

Recommended sequence:

1. stop relying on ETS long-tier durability between restarts
2. configure Tiered to point at Postgres for new long-term writes
3. reinsert any retained ETS long-tier records through the Tiered runtime if you need historical backfill
4. validate retrieval and prune behavior against the Postgres-backed namespace before removing the old ETS path

If you need request-level replay, journaling, or coordinated migration workflows,
that remains a `jido_memory_os` concern rather than a built-in `jido_memory`
feature.

## Durability and Consistency Tradeoffs

Current Postgres backend behavior:

- canonical `Jido.Memory.Record` payloads are preserved exactly using term-binary storage
- `namespace` and `id` lookups are pushed into Postgres directly
- the overlapping structured `Jido.Memory.Query` subset is evaluated in Elixir after a namespace-scoped fetch
- `prune/2` is namespace-scoped and deletes expired records in Postgres directly

This means:

- durability is stronger than ETS for the long tier
- query scalability is currently bounded by namespace-sized scans for structured retrieval
- pruning stays explicit and predictable, but it is not automatic background maintenance

## Current Support Boundaries

Supported now:

- built-in `Jido.Memory.LongTermStore.Postgres`
- built-in `Jido.Memory.LongTermStore.ETS`
- custom backends implementing `Jido.Memory.LongTermStore`

Not yet first-party:

- Redis
- pagination across very large long-tier namespaces
- backend-native metadata querying
- backend-native ranking beyond the canonical overlap

## Open Questions

- when should the Postgres backend move from namespace scans to more selective query pushdown
- whether pagination belongs in the common long-term contract or only in provider-direct extensions
- how much backend-native indexing should be standardized before another durable backend is added
