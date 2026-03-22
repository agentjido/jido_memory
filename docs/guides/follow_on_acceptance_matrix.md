# Follow-On Acceptance Matrix

This matrix defines the supported combinations after the follow-on phases.

## Provider Matrix

| Path | Plugin Surface | Expected Capabilities | Release-Gated |
| --- | --- | --- | --- |
| Built-in `:basic` | `Jido.Memory.Plugin` or `Jido.Memory.ETSPlugin` | Core CRUD and structured retrieval | Yes |
| Built-in `:tiered` with ETS long-term | `Jido.Memory.Plugin` | Core CRUD, tiered retrieval, explainability, lifecycle inspection | Yes |
| Built-in `:tiered` with Postgres long-term | `Jido.Memory.Plugin` | Core CRUD, tiered retrieval, explainability, lifecycle inspection, durable long-term promotion | Yes |
| Built-in `:mirix` | `Jido.Memory.Plugin` for common flows plus `Jido.Memory.Provider.Mirix` for direct advanced flows | Core CRUD, routed retrieval explanations, provider-direct ingestion, provider-direct protected-memory workflows | Yes |
| External-provider reference path | `Jido.Memory.Plugin` | Core CRUD and structured retrieval through a canonical provider | Yes |

Unsupported or non-gated combinations stay explicit:

- external providers are not required to implement Tiered-specific explainability or lifecycle inspection
- built-in `:basic` does not support lifecycle consolidation or explainable retrieval
- built-in `:mirix` keeps ingest and protected-memory workflows provider-direct rather than exposing them through common plugin routes
- Redis is not yet a first-party durable long-term backend

## Long-Term Backend Matrix

| Backend | Used By | Query Expectation | Release-Gated |
| --- | --- | --- | --- |
| `Jido.Memory.LongTermStore.ETS` | Built-in Tiered | Canonical overlapping query subset | Yes |
| `Jido.Memory.LongTermStore.Postgres` | Built-in Tiered | Same overlapping query subset, currently via namespace scan + Elixir filtering | Yes |

The accepted durable query subset is:

- `classes`
- `kinds`
- `tags_any`
- `tags_all`
- `text_contains`
- `since`
- `until`
- `limit`
- `order`

## End-to-End Acceptance Flow

The release-gated acceptance fixture should prove:

1. the same core memory workflow works for Basic, Tiered, Mirix, and the external-provider reference path
2. Tiered explainability remains correct when long-term storage is ETS or Postgres
3. MIRIX retrieval explanations expose routed planner context while keeping canonical record-list retrieval stable
4. MIRIX ingestion and protected-memory workflows remain provider-direct and do not widen the common plugin surface
5. Tiered promotion into the long tier works when the durable backend is Postgres
6. unsupported capabilities still fail cleanly outside the supported matrix

Local and CI release gate:

- `mix test.acceptance`
- `mix quality`

## Non-Goals For This Matrix

- claiming parity for every possible third-party provider
- claiming backend-native query pushdown parity between ETS and Postgres
- expanding the supported durable backend list before the current release matrix is stable
