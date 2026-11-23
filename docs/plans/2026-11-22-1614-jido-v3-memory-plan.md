---
title: Build Jido Memory for Jido v3
type: implementation-plan
date: 2026-11-22
last_reviewed: 2026-11-22
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Build Jido Memory for Jido v3

## Goal Capsule

- **Objective** Give a Jido v3 Agent typed, scoped memory collections with a small set of operations and configurable storage.
- **Means** Build a native Jido Plugin and its `memory` section. Deliver Agent state first, then ETS, Ecto, and optional AshJido storage.
- **Authority** The current task authorizes the temporary directory moves and this plan. The next executor needs local implementation authority. Changes to other repositories, live data, and publication need separate authority.
- **Stop conditions** Stop an affected unit if it cannot prove its version, access, or data guarantees. Keep the local and Ecto units independent of AshJido release timing.
- **Next executor** Jido Memory implementer. Start with U1.

## Product Contract

### Summary

An Agent declares what it can remember. An Action or Flow selects when to remember, recall, or forget. Collections group records with the same schema and select a scope and a store. The first release supports bounded Agent state, ETS, an Ecto Repo, and an optional bridge to an application-owned Ash Resource through AshJido.

### Problem Frame

The current package and provider contract target Jido v2. Jido v3 has new Plugin, Turn, and persistence contracts. The requested fresh start keeps the v2 source and tests available as temporary references while the v3 interface takes shape.

### Actors

- Agent authors declare collections and call memory from Actions and Flows.
- Application owners supply scoped access, supervised storage, database migrations, and Ash Resource Actions when they select those backends.

### Requirements

| ID | Requirement |
| --- | --- |
| R1 | Start on Jido v3 with the v2 source and tests preserved for reference. |
| R2 | Declare typed, scoped collections in an Agent and support remember, recall, and forget. Keep the source Signal reference with each write. |
| R3 | Support bounded memory in Agent state and local external memory in ETS. |
| R4 | Support queryable memory through the host Ecto Repo. Verify PostgreSQL and SQLite. |
| R5 | Support application-owned Ash Resources through explicit Action bindings when a compatible AshJido is installed. Preserve Ash authorization and tenant scope. |
| R6 | Document the v2 boundary, backend behavior, and the evidence required before a v3 release or retirement of legacy code. |

### Key Flows

1. The author enables the memory Plugin, declares a collection, and gives it a Joi schema. The default scope is the Agent instance.
2. An Action returns a memory Directive. The Plugin validates it and either applies it to Agent state or queues a write for an external store.
3. An Action recalls scoped records with exact filters and a bounded limit. Results include source references. A later Turn reads a committed state write. An external read can see the write after the adapter acknowledges it.

### Acceptance Examples

- A ticket resolution is present after a successful Turn and absent after a failed Turn. A second Agent with the same record key has its own value.
- An Ecto-backed collection returns the same scoped results on PostgreSQL and SQLite, including after a restart.
- An Ash-backed collection uses the configured Actions. Permitted Actors can use the collection. A different tenant or an Actor denied by an Ash policy receives no record.

### Success Criteria

An implementer can run one example Agent with each supported store, observe the documented commit behavior, and verify each backend with the same record contract. The Ash-free build compiles and runs the core tests.

### Scope Boundaries

This plan covers the core memory contract, storage, and the transition boundary. Future work covers automatic capture, lexical and vector search, graphs, consolidation, Redis parity, provider moves, and data import. Each legacy provider remains a v2 consumer until it has an explicit migration.

### Key Decisions

Use the three public operations from the DSL draft. Require a host-selected adapter binding for external collections. Keep Agent checkpoints and queryable memory records as separate storage contracts.

### Rejected Alternatives

The branch keeps the v2 provider stack as a temporary reference. Carrying its provider registry and capabilities into v3 would make those legacy contracts part of the first v3 release.

### Dependencies

- Jido `3.0.0-beta.3` is the released implementation baseline. Recheck the exact resolved version before widening the constraint.
- The Ecto matrix needs an application Repo for each SQL driver and a disposable database or file.
- The Ash matrix needs a compatible consolidated-v3 AshJido build. The released AshJido tag and a promising local commit are identified below.

### Outstanding Questions

The fresh implementation can start. A future release needs a decision from the package owner on the supported AshJido release and the transition of existing provider installations and data.

### Sources

- [Memory DSL draft](jido-v3-memory-dsl.md)
- [Jido beta.3 source](https://github.com/agentjido/jido/tree/v3.0.0-beta.3)
- [AshJido v3 Action guide](https://github.com/agentjido/ash_jido/blob/ae6ebdfadad0676ce5047a6b8aa580cd66ad7012/guides/getting-started.md)

## Planning Contract

### Product Contract Preservation

Product Contract unchanged. The implementation plan maps the draft's `memory` block to the API in the released Jido beta and carries forward its collection, record, operation, and storage boundaries.

### Current System

`mix.exs` compiles `lib` and `test/support` and resolves Jido v2 plus the separate Action and AI packages. `BasicPlugin` attaches the old actions and capture hooks. `Runtime` selects a provider and the Basic provider delegates to the store. [BasicPlugin](https://github.com/agentjido/jido_memory/blob/09e2ddbf0a35ec54349b5c5d4f36ca369ceaa7d7/lib/jido_memory/basic_plugin.ex) · [Store contract](https://github.com/agentjido/jido_memory/blob/09e2ddbf0a35ec54349b5c5d4f36ca369ceaa7d7/lib/jido_memory/store.ex)

The old stores include ETS, Redis, and PostgreSQL. The PostgreSQL store uses a caller-owned Ecto Repo and PostgreSQL-specific SQL. Mem0 and MemPalace use a path dependency on this repository. KG uses its Git `main` branch. All three consume v2 provider interfaces. [PostgreSQL store](https://github.com/agentjido/jido_memory/blob/09e2ddbf0a35ec54349b5c5d4f36ca369ceaa7d7/lib/jido_memory/store/postgres.ex)

### Target System

`memory` section → static collection definitions → Action or Flow → scoped read or typed Directive → Agent commit or pending external operation. A small public facade and one Plugin own this path. External adapters implement a common record contract. The app owns the Ecto Repo or Ash Resource and its supervision.

### Key Technical Decisions

- **KTD1 · Plugin declaration.** Use `use Jido.Agent, name: "support", plugins: [Jido.Memory.Plugin]`. The Plugin contributes the `memory` section through `use Jido.Plugin, sections: ...` and lowers static declarations through `lower/2`. The Plugin imports the `memory FlowModule do` form. Use the released extension path so the DSL and Plugin work on the stated baseline. Governs R1–R2, U1, and U1a. [Jido beta.3 Plugin source](https://github.com/agentjido/jido/blob/v3.0.0-beta.3/lib/jido/plugin.ex) · [DSL precedent](https://github.com/agentjido/jido/blob/v3.0.0-beta.3/lib/jido/ai/agent/plugin.ex)
- **KTD2 · Record and query.** Use `{scope, collection, key}` as identity. Validate portable payloads and declared fields with Joi. `remember` upserts and `forget` is idempotent. `recall` returns a list ordered by recency with a stable tie-break. Exact-match filters accept declared scalar fields. Reads use an explicit result limit with validated defaults and maxima. The first public contract uses these bounded operations. Provider-native search can extend it later. Governs R2–R5 and U1–U5.
- **KTD3 · Commit boundary.** `state_spec/1` owns `:memory`. Directives modify state through `reduce/2` in batch order. Put and delete on an external store follow commit and have a separate acknowledgement. Save pending requests in the Plugin field and recover them from `Jido.Plugin.Init` on activation. A post-commit hook can wake the worker. Jido does not replay that hook, so readiness and recovery come from the committed queue. Governs R3–R5 and U1–U5. [Post-commit work](https://github.com/agentjido/jido/blob/v3.0.0-beta.3/guides/plugins/plugin-post-commit-work.md) · [Plugin resource lifecycle](https://github.com/agentjido/jido/blob/v3.0.0-beta.3/guides/plugins/plugin-supervised-resources.livemd)
- **KTD4 · External adapter contract.** Implement `put`, `get`, `query`, and `delete` with scoped keys. Mutations also receive a stable operation ID. A durable adapter atomically applies the effect and records the operation result so a retry cannot replay an older change over a newer one. The backend owns its record order and resolves concurrent writes in commit order. Begin with this contract before adding backend-specific features. Governs R3–R5 and U2–U5.
- **KTD5 · Ash authorization.** Bind four explicit AshJido-generated Actions and normalize their result envelopes at the adapter. A trusted runtime resolver supplies actor and tenant in `context.ash`. Persist portable actor and scope references for replay and resolve authorization again at execution. The resource owns unique identity and atomic write and receipt behavior. `AshJido.Persistence.Adapter` is an opaque checkpoint store and supplies a separate integration. Governs R5 and U2/U5. [AshJido Action context](https://github.com/agentjido/ash_jido/blob/ae6ebdfadad0676ce5047a6b8aa580cd66ad7012/guides/getting-started.md) · [AshJido checkpoint adapter](https://github.com/agentjido/ash_jido/blob/ae6ebdfadad0676ce5047a6b8aa580cd66ad7012/guides/persistence.md)

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| `mix.exs`, `mix.lock`, `lib`, `test` | V2 build with separate Jido packages | Build active paths against consolidated Jido v3 and include only active source in the package | Breaking change for existing callers |
| Agent state | V2 `BasicPlugin` | Own one field with bounded collections and portable pending operations | V2 snapshots need a separate conversion decision |
| External stores | V2 provider and store APIs | One scoped record API with an explicit write receipt | Agent commit only confirms intent. An adapter receipt confirms storage. |
| Ecto | PostgreSQL-specific adapter | Versioned, host-owned memory migration and fields for querying scoped records | Test both drivers. Keep v2 data in its existing table. |
| Ash | V3 branch can generate Actions and store checkpoints | Add optional memory Action bindings and an Ash Resource fixture | An unavailable dependency or invalid binding fails configuration when selected. |
| Sibling providers and examples | V2 Runtime and types | Document compatible revision and migration sequence. Rewrite package examples for v3. | Existing local path dependencies can break at the directory move. |

### Implementation Units

#### U1 · Run one Agent with state-backed memory

- **Outcome and requirements** R1–R3. A fresh Agent declares a collection and remembers, recalls, and forgets a typed record.
- **Dependencies** None.
- **Surfaces and direction** Create `lib` and `test` with the new facade, Plugin, DSL section, directives, and tests. Update Mix dependencies and the lockfile for released beta.3. Remove separate v2 Jido dependencies once active references are gone. Keep the moved trees out of compilation and packaging. Validate declaration names, schema, limits, and store references. Use the configured size limit to evict the oldest write. Use the starting state for Action reads. Verify state through the Jido snapshot and restore API.
- **Tests and gate** Compile the real Agent module and run it through `Jido.Agent.cmd/3`. Cover replacement, source ID, ordering, eviction, invalid entry rollback, unknown collection, and snapshot restore. Complete when `mix test` runs this new slice and the old source stays excluded.

#### U1a · Recall evidence inside an Agent reasoning Flow

- **Outcome.** The [first LLM ladder example](../examples-ladder.md#00--give-the-model-evidence)
  sends a question through the Agent. One named read grant selects an
  Agent-state collection, allowed filters, exposed fields, and a record limit.
- **Dependencies.** U1 and the pinned Jido AI Actions.
- **Surfaces and direction.** Bind the grant to the reasoning Flow with
  `memory FlowModule do`. Put `Jido.Memory.Actions.RecallForModel` between
  `ProjectConversation` and `CallModel`. Resolve the Flow and grant from
  trusted Agent preparation. Read through `Memory.recall/3` and add the
  projected evidence to the open model context. Keep capture and writes
  in their own examples.
- **Tests and gate.** Exercise the Agent question Signal with recall on and off.
  Check that only approved fields reach the prepared model request and that
  a different root Flow or an unapproved filter cannot use the grant. Run the
  example with the offline fixture and LM Studio.

#### U2 · Prove scoped writes and acknowledgement with ETS

- **Outcome and requirements** R2–R5. Prove the shared external-store contract on one live Agent with supervised ETS.
- **Dependencies** U1.
- **Surfaces and direction** Add `Jido.Memory.Store`, one contract test case, runtime scope admission, a supervised queue worker, and ETS. Accept external mutations from a live Action context. Use an application-supplied resolver for scope and actor references. The reducer validates and records pending requests. The worker drains one operation at a time per Agent. Give each request a stable ID derived from Agent identity, Signal ID, and Directive position. Preserve order on retry. Record outcomes through an authenticated internal acknowledgement Turn. Keep the queue bounded. Retry transient failures with bounded backoff and surface a terminal failure or exhaustion without losing its status. For ETS, the table owner defines lifetime and the test proves recovery only while the table survives. A pure `cmd/3` never accesses the external store.
- **Tests and gate** Run contract tests for get, query, put, and delete across two scopes. Exercise failed Turns, missing live context, duplicate delivery, restart before write and after write before acknowledgement, and retry after a later write or delete. Complete when the live Agent reports confirmed and terminal outcomes and the same tests can be reused for durable adapters.

#### U3 · Store scoped records through Ecto

- **Outcome and requirements** R4. Applications use their Repo on PostgreSQL or SQLite.
- **Dependencies** U2.
- **Surfaces and direction** Add an optional Ecto adapter, host-run versioned migration, disposable test Repos, and schema and query mapping. Use a unique scoped key, typed scalar filter encoding tested on both drivers, and stable recency order. Commit each record mutation and its operation receipt in one transaction. Give the new tables distinct names from v2. Require the SQL dependency and a supported driver only when configured.
- **Tests and gate** Run the shared contract and concurrent upsert, repeated delete, retry, and restart scenarios against both database engines. Assert that the new migrations touch only the v3 tables. Complete when both drivers pass and core works without Ecto.

#### U4 · Prepare and verify the AshJido version fixture

- **Outcome and requirements** R5. Establish the exact compatible AshJido dependency and Action envelope for the implementation.
- **Dependencies** U1 supplies the pinned consolidated-v3 version.
- **Surfaces and direction** Verify the selected dependency in a consumer fixture. Hex currently exposes AshJido `3.0.0-beta.1`. Its tag still declares the separate Jido Action and Signal packages. The local AshJido commit `e4374e8` targets Jido `3.0.0-beta.3` and is one commit ahead of the inspected `origin/release/v3`. Start development from a clean fixture at that exact commit if a compatible published build is unavailable. Confirm Action result envelopes and absence of module conflicts. Record the chosen dependency source. Use a released compatible build for the release gate.
- **Tests and gate** Compile concrete generated Actions against the same Jido version, execute them through `Jido.Exec.run/3`, and verify the expected result and Ash actor and tenant propagation. Complete when U5 has a reproducible dependency and fixture. If that source fails to compile, record the failure and keep U1–U3 available.

#### U5 · Store scoped records through AshJido

- **Outcome and requirements** R5. A configured collection uses an existing application Resource and explicit Action bindings.
- **Dependencies** U2 and U4.
- **Surfaces and direction** Add `Jido.Memory.Store.Ash` with lazy optional integration. Use the consumer fixture to show scoped Action schemas, actor and tenant context, and result normalization. Require the application's Actions to enforce authorization and to apply the mutation and operation receipt atomically. A single-shot Action or a transaction inside the Resource can hold that contract. Keep Resource setup under application ownership.
- **Tests and gate** Run the shared store contract plus missing bridge, invalid bindings, denied Action, cross-tenant reads and writes, permission change before replay, and ambiguous write retry through real AshJido Actions and a disposable Resource. Complete when policy and replay tests pass and the default build still runs without AshJido.

#### U6 · Verify integration and prepare the package boundary

- **Outcome and requirements** R1–R6. One user-facing guide, a runnable v3 example, and evidence for each store and the transition.
- **Dependencies** U1, U1a, and U2–U5.
- **Surfaces and direction** Update `README.md`, guides, examples, and tests used by CI. Label v2 docs and example references. Verify ExDoc and Hex package files include the active tree. Record minimum versions, Release and migration order, and the consumer boundary for KG, Mem0, and MemPalace. Keep their updates outside this checkout until authorized.
- **Tests and gate** Run normal package quality and documentation checks, all backend matrices, and a package dry run. Record any consumer whose compatibility still needs an authorized check. Complete when the Definition of Done can be proved on the final tree.

### Work Graph

Start with U1 and follow it with U1a for the first model-facing example. U2 and U4 can proceed independently after U1. U3 follows U2. U5 needs both U2 and U4. U6 combines the results. The Ash dependency check gates the Ash path and final release proof. It leaves the Agent-state, ETS, and Ecto paths free to proceed.

### Verification Contract

Run package checks from the `jido_memory` repository. Add the adapter matrix in the implementation with documented fixture commands, migrations, and prerequisites. Use disposable databases and explicit dependencies for these runs.

| Requirements | Units | Required evidence |
| --- | --- | --- |
| R1, R2 | U1, U1a, U6 | Fresh compile against selected Jido v3, real Agent Turn tests, recall traces with the fixture and LM Studio, and complete package dry run |
| R3 | U1, U2 | Snapshot and restore, backend parity, retry and ordering, and failed Turn isolation |
| R4 | U2, U3 | PostgreSQL and SQLite contract runs, transaction and restart tests, and build without Ecto |
| R5 | U2, U4, U5 | Real generated Actions, Ash isolation and authorization, idempotent retry, and build without AshJido |
| R6 | U6 | Runnable example, current guides, documented consumer limits, and package contents |

```sh
mix format --check-formatted
mix test
mix quality
mix docs -f html -f markdown
package_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/jido-memory-package.XXXXXX")
mix hex.build --unpack --output "$package_check_dir/package"
```

### Rollout and Recovery

Treat the v3 release as breaking. Keep a v2 release or immutable Git revision for current consumers. Qualify Jido first, then the compatible optional AshJido release, then v3 Jido Memory, then migrated consumers. Before publishing v3, the package owner decides whether to pin KG to v2 or move it first because KG currently follows Git `main`. Mem0 and MemPalace need either a v2 checkout or explicit porting for local use.

Deploy new tables alongside v2 storage. If a local or staged rollout fails, disable the v3 writer and keep both datasets. Reconcile unacknowledged operations before a restart or rollback. A later import from v2 needs a separate plan and data verification. Retire the temporary directories only after the v3 implementation and migration reference needs have been reviewed.

### Risks and Assumptions

- External acknowledgement can be lost after a successful write. Keep operation receipts for as long as queued work can be replayed. Test a retry after a newer write or delete. Reject a direct rollout when the selected Resource cannot provide atomic effect and receipt behavior.
- Recovery must protect scope. Reload authorization from trusted references and record terminal failure if access changed. Logs and status carry operation IDs and result classes with no payloads or actor credentials.
- A local commit that pins Jido beta.3 is evidence of development direction. The Ash build remains unverified until U4 compiles and runs the fixture.
- The directory moves intentionally prepare an empty active source and test layout. Current v2 test results do not apply to that layout. The sibling providers were inspected as source consumers.

### Open Planning Decisions

- **Before Ash release qualification** The dependency owner must identify a published compatible AshJido build. U4 can use an exact source revision during development. Publication timing controls the final Ash release gate.
- **Before consumer migration or retirement** The package owner decides which v2 installations need data migration and when the temporary trees can be removed. An authorized follow-up must verify the chosen consumers.

### Definition of Done

- A v3 Agent can declare, write, recall, and forget a scoped record on all first-release storage targets.
- State-backed changes commit with the Turn. External changes report their own confirmed outcome and pass the recovery and isolation checks.
- The optional dependency matrix, docs, example, package checks, and transition evidence pass. A missing published AshJido build remains a release gate even if the source fixture passes.
- Fresh `lib` and `test` paths are active. The temporary v2 directories are outside compile, test, and package inputs.

### Planning Sources

- [Mix project and aliases](../../mix.exs)
- [Jido beta.3 source](https://github.com/agentjido/jido/tree/v3.0.0-beta.3) and [Hex release](https://hex.pm/packages/jido/3.0.0-beta.3)
- [AshJido release list](https://hex.pm/api/packages/ash_jido) and [published beta.1 dependency declarations](https://github.com/agentjido/ash_jido/blob/v3.0.0-beta.1/mix.exs)

## Adapter Results

- Markdown is canonical at `docs/plans/2026-11-22-1614-jido-v3-memory-plan.md`.
- HTML and Beadwork were not requested.
