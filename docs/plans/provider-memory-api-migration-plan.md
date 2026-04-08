# Provider-First Memory API Migration Plan

## Purpose

This document defines the migration path for evolving `jido_memory` from its current ETS/store-centric design into the canonical Jido memory API with pluggable provider implementations such as `jido_memory_mempalace` and `jido_memory_mem0`.

The goal is not to make `jido_memory` itself become MemPalace or Mem0. The goal is to make `jido_memory` the stable, typed, provider-neutral interface that agents and applications depend on regardless of which memory system sits behind it.

## Current State

The current local baseline in `jido_memory` is:

- `Jido.Memory.Runtime` is store-centric and directly resolves `namespace` and `store`.
- `Jido.Memory.Store` is the main abstraction boundary.
- `Jido.Memory.BasicPlugin` is the canonical plugin surface.
- `Jido.Memory.Record` and `Jido.Memory.Query` are the only canonical typed memory structs.
- Retrieval returns bare `[Record.t()]`.
- There is no provider registry, provider bootstrap, provider capability discovery, or provider contract test suite.

This is a solid v1 for simple ETS-backed memory, but it is not yet the right abstraction for external memory systems with different ingestion, retrieval, and maintenance semantics.

## Target Outcome

`jido_memory` becomes the canonical API package for Jido memory.

It owns:

- stable public runtime facade
- canonical memory structs
- provider behaviours
- capability behaviours
- provider registry and bootstrap helpers
- plugin and action surfaces
- provider contract tests
- migration and documentation story

External implementation packages own concrete memory systems:

- `jido_memory_mempalace`
- `jido_memory_mem0`
- future providers such as `jido_memory_mirix`, `jido_memory_zep`, or others

## Architectural Direction

The design must separate two concerns clearly:

- `Store` answers: "How are canonical records persisted and queried?"
- `Provider` answers: "How does a memory system ingest, retrieve, explain, scope, and maintain memory?"

This distinction is critical.

`Store` remains useful for:

- ETS
- Postgres record persistence
- simple durable storage
- provider internals

`Provider` becomes the top-level memory abstraction for:

- basic memory
- tiered memory
- MemPalace-style episodic evidence memory
- Mem0-style extracted/reconciled memory
- future graph or hybrid systems

## Canonical API Principles

The common API must be:

- stable
- typed
- narrow
- backend-neutral
- capability-aware

The common API must not:

- flatten all providers to a useless lowest common denominator
- force provider-native semantics into `Store`
- return loose maps when agents need reliable shapes
- let the first sophisticated provider define the API accidentally

## Canonical Public Surface

### Core structs

`jido_memory` should own these canonical structs:

- `Jido.Memory.Record`
- `Jido.Memory.Query`
- `Jido.Memory.Scope`
- `Jido.Memory.Hit`
- `Jido.Memory.RetrieveResult`
- `Jido.Memory.Explanation`
- `Jido.Memory.IngestRequest`
- `Jido.Memory.IngestResult`
- `Jido.Memory.CapabilitySet`
- `Jido.Memory.ProviderInfo`
- `Jido.Memory.ConsolidationResult`

### Core behaviours

`jido_memory` should own these behaviours:

- `Jido.Memory.Provider`
- `Jido.Memory.Capability.Ingestion`
- `Jido.Memory.Capability.ExplainableRetrieval`
- `Jido.Memory.Capability.Lifecycle`

`Jido.Memory.Store` remains as the persistence substrate, not the memory-system abstraction.

### Runtime facade

Canonical runtime operations:

- `remember/3`
- `get/3`
- `forget/3`
- `retrieve/3`
- `capabilities/2`
- `info/3`
- `ingest/3` when supported
- `explain_retrieval/3` when supported
- `consolidate/2` when supported

Compatibility rule:

- `retrieve/3` becomes the canonical read path and returns `RetrieveResult`

### Plugin and actions

Canonical plugin surface:

- `Jido.Memory.BasicPlugin`

Canonical actions:

- `memory.remember`
- `memory.retrieve`
- `memory.forget`

## Common vs Provider-Direct Boundaries

The common runtime should only include operations that can be defined cleanly across providers.

These likely belong in the common API:

- direct record write
- direct record fetch
- structured retrieval
- scoped retrieval result
- capability discovery
- retrieval explanation
- optional ingestion
- optional lifecycle consolidation

These should remain provider-direct unless multiple implementations converge on the same shape:

- MemPalace taxonomy graph tools
- MemPalace wake-up or layered recall extras
- Mem0 feedback flows
- Mem0 export/history flows
- Mem0 reconciliation maintenance controls
- provider-specific governance or vault operations

The common surface should be narrow and typed. Provider-native surfaces can be richer.

## Current Gaps

### Gap 1: Wrong top-level abstraction

Current `jido_memory` assumes a memory backend is a `Store`.

That is insufficient for MemPalace and Mem0 because they differ in:

- ingestion pipelines
- retrieval semantics
- scoped identity
- explanation semantics
- maintenance and consolidation behavior

### Gap 2: Missing typed result objects

The current package has `Record` and `Query`, but not:

- retrieval hits
- retrieval results
- explanation payloads
- ingest request/result types
- capability model
- provider info model

Without these, agents still need provider-specific logic.

### Gap 3: Retrieval is too thin

Current retrieval returns `[Record.t()]`.

That loses:

- score
- rank
- matched-on reason
- provider origin
- tier or memory-type origin
- provider extensions

Those are exactly the fields a stable cross-provider API should standardize.

### Gap 4: Plugin is ETS-first, not provider-first

The current plugin identity should be `BasicPlugin`.

That bakes the storage mechanism into the public story instead of making Jido memory provider-driven.

### Gap 5: No capability discovery

There is no canonical way to ask:

- does this provider support ingestion?
- explainable retrieval?
- lifecycle consolidation?
- graph augmentation?
- protected memory?

### Gap 6: No provider bootstrap ownership model

There is no formal caller-owned bootstrap path for provider child specs or runtime processes.

That matters for more complex providers that may need supervised infrastructure.

### Gap 7: No contract suite for external adapters

There is currently no reusable test suite that external provider packages must pass in order to claim compatibility.

Without that, compatibility claims will drift.

### Gap 8: `jido_memory_os` value not yet harvested

`jido_memory_os` already contains useful ideas for:

- long-term backend boundaries
- richer retrieval query planning
- capability-aware flows
- migration helpers

Those ideas need to be harvested into `jido_memory` selectively, not copied wholesale.

## Desired Package Topology

Canonical package:

- `jido_memory`

External implementation packages:

- `jido_memory_mempalace`
- `jido_memory_mem0`

Possible later packages:

- `jido_memory_mirix`
- `jido_memory_zep`
- `jido_memory_pgvector`

Dependency direction:

- external implementation packages depend on `jido_memory`
- `jido_memory` does not depend on MemPalace or Mem0 packages

This keeps the contract central and implementations modular.

## Migration Strategy

The migration should be additive and compatibility-first.

Do not replace the current API in one jump.

Instead:

1. introduce provider-first internals
2. wrap current behavior with `Provider.Basic`
3. add typed richer APIs
4. keep the Jido integration narrow around `BasicPlugin`
5. move users toward `retrieve`

## Phased Execution Plan

### Phase 1: Freeze the API contract

Define and approve:

- canonical structs
- provider callbacks
- capability behaviours
- compatibility policy
- runtime result shapes
- provider-direct boundary rules

Deliverables:

- approved API spec document
- approved list of canonical structs
- approved common vs provider-direct rules

Exit criteria:

- no major unresolved questions about the public contract

### Phase 2: Introduce provider core into `jido_memory`

Add:

- `Jido.Memory.Provider`
- capability behaviours
- `Jido.Memory.ProviderRef`
- `Jido.Memory.ProviderRegistry`
- `Jido.Memory.ProviderBootstrap`
- `Jido.Memory.Provider.Basic`

Use `Provider.Basic` as a wrapper over the current store-based runtime behavior.

Deliverables:

- provider-aware runtime dispatch
- basic provider backed by current `Store`
- provider aliasing for built-ins

Exit criteria:

- current remember/get/forget/recall flows still work
- ETS path operates through `Provider.Basic`

### Phase 3: Add canonical typed result structs

Add:

- `Scope`
- `Hit`
- `RetrieveResult`
- `Explanation`
- `CapabilitySet`
- `ProviderInfo`
- `IngestRequest`
- `IngestResult`
- `ConsolidationResult`

Extend `Query` to support safe provider extensions and richer retrieval metadata.

Deliverables:

- new canonical structs
- serialization and validation logic
- docs for each shared struct

Exit criteria:

- common runtime no longer uses loose maps for shared retrieval and capability outputs

### Phase 4: Move runtime to canonical provider semantics

Change `Runtime` so that:

- `retrieve/3` is canonical and returns `RetrieveResult`
- `recall/2` is compatibility-only
- `capabilities/2` returns `CapabilitySet`
- `info/3` returns `ProviderInfo`
- optional capability routes dispatch through provider behaviours

Deliverables:

- provider-aware runtime
- canonical result normalization preserved
- error model updated for unsupported capability cases

Exit criteria:

- `Runtime` no longer assumes `Store` is the top-level backend abstraction

### Phase 5: Introduce provider-aware plugin and actions

Add canonical plugin:

- `Jido.Memory.BasicPlugin`

Add actions:

- `memory.retrieve`

Deliverables:

- provider-aware plugin config
- provider-aware action routing
- updated plugin docs and examples

Exit criteria:

- agent code can use providers without coupling to ETS

### Phase 6: Add provider contract test suite

Create reusable provider contract tests inside `jido_memory`.

The contract suite should verify:

- provider initialization
- capability normalization
- remember/get/forget core flow
- retrieve result shape
- explanation shape when supported
- unsupported-capability behavior
- compatibility behavior for `recall`

Deliverables:

- provider contract helper module
- shared provider contract tests
- guidance for external provider packages

Exit criteria:

- `Provider.Basic` passes the suite
- the suite is reusable from external repos

### Phase 7: Harvest the best ideas from `jido_memory_os`

Harvest selectively:

- long-term store boundary
- richer retrieval-query ideas
- tiered lifecycle ideas that fit the common contract
- migration or parity-test material

Do not copy:

- heavy control-plane machinery
- governance or ops surfaces that do not belong in core
- a second package narrative

Deliverables:

- extracted concepts adapted into `Jido.Memory` terminology
- updated tests and docs proving the adaptation

Exit criteria:

- useful `MemoryOS` ideas live in `jido_memory`
- no duplicate public abstraction story remains

### Phase 8: Create `jido_memory_mempalace`

External package implements:

- `Jido.Memory.Provider`
- `Jido.Memory.Capability.Ingestion`
- `Jido.Memory.Capability.ExplainableRetrieval`

Core mapping:

- raw drawers or episodic evidence map into canonical `Record`
- retrieval returns canonical `Hit` and `RetrieveResult`
- raw evidence remains the source of truth

Provider-direct extras may include:

- taxonomy introspection
- graph navigation
- wake-up/layered recall

Deliverables:

- provider implementation package
- provider contract tests passing
- example integration with `Jido.Memory.Runtime`

Exit criteria:

- agents can use MemPalace through the shared runtime facade

### Phase 9: Create `jido_memory_mem0`

External package implements:

- `Jido.Memory.Provider`
- `Jido.Memory.Capability.Ingestion`
- `Jido.Memory.Capability.ExplainableRetrieval`

Core mapping:

- extracted or reconciled facts map into canonical `Record`
- scoped identity maps into canonical `Scope`
- retrieval returns canonical `Hit` and `RetrieveResult`

Provider-direct extras may include:

- feedback
- history
- export
- maintenance and refresh operations

Deliverables:

- provider implementation package
- provider contract tests passing
- example integration with `Jido.Memory.Runtime`

Exit criteria:

- agents can use Mem0 through the shared runtime facade

### Phase 10: Documentation and migration cleanup

Update all public documentation so that:

- `jido_memory` is clearly the canonical package
- ETS is presented as the basic built-in provider path
- MemPalace and Mem0 are presented as implementations
- compatibility paths are documented and eventually de-emphasized

Deliverables:

- updated README
- migration guide
- provider author guide
- example agent integrations

Exit criteria:

- docs reflect the provider-first architecture consistently

## Recommended PR Sequence

Suggested incremental PRs:

1. API spec and planning docs
2. provider core and `Provider.Basic`
3. typed retrieval and provider metadata structs
4. runtime provider dispatch and compatibility shims
5. provider-aware plugin and `memory.retrieve`
6. provider contract tests
7. harvested long-term/tiered concepts from `jido_memory_os`
8. `jido_memory_mempalace`
9. `jido_memory_mem0`
10. docs and migration pass

## Acceptance Criteria

The migration is successful when:

- `jido_memory` is the canonical Jido memory API
- agents depend on stable structs and behaviours rather than backend details
- ETS/basic remains simple and non-regressed
- MemPalace and Mem0 both fit naturally as provider implementations
- common runtime operations are typed and capability-aware
- external providers can prove compatibility through shared contract tests

## Risks

### Risk: designing around one provider

If the API is shaped around MemPalace only, it will underfit Mem0.
If shaped around Mem0 only, it will underfit evidence-first systems.

Mitigation:

- use `Basic`, `MemPalace`, and `Mem0` as the proving set

### Risk: leaking provider-specific flags into the common facade

Mitigation:

- keep provider-native operations provider-direct
- use typed `extensions` only where necessary

### Risk: preserving too much of the store-centric story

Mitigation:

- keep `Store`, but demote it to provider infrastructure

### Risk: importing too much from `jido_memory_os`

Mitigation:

- harvest only what strengthens the canonical package
- leave heavy control-plane machinery behind unless proven necessary

## Immediate Next Step

The next concrete step is to convert this planning document into a formal API specification for:

- provider callbacks
- canonical structs
- runtime return types
- compatibility rules
- provider-direct extension boundaries

That API specification should be approved before implementation begins.
