# Jido Memory Execution Plan

Status date: 2026-04-08

This document is the concrete execution plan for turning `jido_memory` into the stable canonical memory API and adapter surface.

## What We Have Today

`jido_memory` already has the foundation in place.
  
- Core runtime delegates to provider modules via `resolve_provider`.
- Provider behavior is defined and enforced by `Jido.Memory.Provider`.
- Provider resolution and schema validation live in `Jido.Memory.ProviderRef`.
- A built-in provider implementation exists as `Jido.Memory.Provider.Basic`.
- Plugin metadata/state includes `provider` and `provider_opts`.
- Action flows (`remember`, `recall`, `forget`) pass through runtime and preserve current call forms.
- Test coverage exists for plugin lifecycle, runtime operations, and provider parsing/validation.
- Validation so far:
  - `mix compile`
  - `MIX_ENV=test mix test --no-start`

## Workstream Definition

Goal: keep `Jido.Memory.Runtime` as the stable API and move advanced memory behavior into composable packages.

Primary decision:
1. `jido_memory` owns the canonical runtime, plugin, schemas, and provider contract.
2. Advanced providers ship in dedicated packages (for example `jido_memory_mempalace`, `jido_memory_mem0`) with their own dependency stacks.
3. New APIs are added only where they can be used consistently across providers; otherwise use provider-direct APIs in provider packages.

## Phase 1 - Stabilize Core (Week 1)

Goal: make the current provider abstraction production-safe before adding new packages.

1. Finalize provider option precedence and validation
   - Define final precedence chain for runtime options:
     1. explicit runtime opts
     2. query attrs
     3. plugin state
     4. provider base defaults
   - Ensure all precedence branches validate types and return deterministic errors.
   - Add tests:
     - invalid `provider_opts` in each layer
     - conflicting `provider` values across layers
     - fallback to `Basic` when `provider` is omitted
   - Acceptance: invalid config always returns a typed error from runtime boundary, no runtime crash.

2. Lock backward compatibility behavior
   - Keep both `retrieve/3` and `recall/2`, with `recall/2` using existing `recall(%{})` semantics.
   - Preserve tuple return shapes used by actions and runtime callers.
   - Add explicit docs for result shape compatibility notes.
   - Acceptance: existing `Jido.Memory.*` callers continue functioning with no behavior change in default path.

3. Tighten plugin-provider handoff
   - Ensure `ETSPlugin.mount/2` persists provider metadata predictably (`provider`, `provider_opts`, plus optional namespace/store overrides).
   - Confirm action-driven calls (through `Handle_signal` and actions) still route through runtime provider path.
   - Acceptance: plugin path with and without provider config behaves identically for Basic behavior.

4. Add provider-specific failure coverage
   - Add tests for:
     - provider module not loaded
     - module missing required behavior callbacks
     - provider-specific `validate_config` failures
     - provider contract methods returning errors
   - Acceptance: runtime returns `{ :error, reason }` without leaking private exceptions.

## Phase 2 - Contract Polishing for Third-Party Providers (Week 2)

Goal: define the “official contract” that external provider packages can target.

1. Introduce a minimal capability query
   - Add/confirm provider metadata API on `info/2` and establish expected fields:
     - `:name`
     - `:version`
     - `:capabilities`
     - optional `:supports` map
   - Keep compatibility by allowing partial maps and returning defaults.
   - Acceptance: runtime can render provider capabilities without provider-specific code.

2. Publish a provider input model
   - Add canonical types for provider opts that are common to all providers (`:namespace`, `:store`, future `:index`, `:embedding_model` hints where applicable).
   - Add explicit docs for provider-agnostic fields versus provider-specific extras.
   - Acceptance: new provider authors can implement with clear guidance and less guesswork.

3. Add adapter interoperability docs and quickstart
   - Add `docs/provider_contract.md` with:
     - required callbacks and callback invariants
     - minimal happy-path provider implementation skeleton
     - contract tests checklist
   - Acceptance: one new package can integrate without reading plugin internals.

4. Add provider reference aliases
   - Support known aliases (`:basic`, `:mempalace`, `:mem0`) in runtime/plugin entry paths with safe handling of invalid aliases.
   - Keep aliases additive and optional.
   - Acceptance: users can switch by alias once ecosystem packages exist.

## Phase 3 - Package Splits and External Implementations (Weeks 3-6)

Goal: implement advanced providers without overloading the core package.

1. Create `jido_memory_mempalace`
   - Package scaffold:
     - dependency on `jido_memory`
     - adapter that maps MemPalace raw chunk graph/taxonomy outputs into `Jido.Memory.Record` and retrieval result sets
     - provider module(s) implementing core callbacks only
   - Runtime contract coverage:
     - remember/get/retrieve/forget/prune with provider-specific options
     - namespace interoperability with plugin and action flows
   - Acceptance: same tests as Basic path run against MemPalace provider module.

2. Create `jido_memory_mem0`
   - Package scaffold:
     - dependency on `jido_memory`
     - optional dependencies scoped to adapter.
   - Implement core callbacks and any required normalization from Mem0 payloads to `Record`.
   - Acceptance: core runtime features work and unsupported features degrade with explicit errors.

3. Add optional provider packages for legacy built-ins if needed
   - Keep any tiered/mirix-like providers out of core unless already stable as universal runtime features.
   - Only add where provider value is clear and contract remains canonical-safe.
   - Acceptance: no provider-specific complexity leaks into `Jido.Memory.Runtime`.

4. Build provider interoperability test suite
   - Add a shared test module in `test/support/provider_contract_test.exs`:
     - shared examples for the callback surface
     - expectations for idempotency and query behavior
     - namespace and pruning semantics
   - Acceptance: every provider package can run the same contract tests.

## Phase 4 - Canonical Package Framing (Weeks 5-6)

Goal: make canonical direction explicit and migration friction low.

1. Refresh `jido_memory` README
   - Update to present `jido_memory` as the canonical package.
   - Add provider mode section with examples for:
     - Basic local memory
     - MemPalace backend
     - Mem0 backend
   - Add migration examples for old store-style configs.
   - Acceptance: developers can onboard to provider mode from one page.

2. Add deprecation and migration notes
   - Preserve ETS/local behavior as stable default.
   - Document planned evolution and recommended path for power users.
   - Acceptance: no ambiguous messaging that suggests multiple canonical packages.

3. Add changelog/spec updates
   - Update CHANGELOG and `.spec` with provider support matrix:
     - stable
     - experimental
     - external dependency required
   - Acceptance: release claims match tested implementation status.

## Phase 5 - Quality, Gates, and Release Readiness (Weeks 7+)

1. Establish provider matrix CI
   - Keep `jido_memory` CI independent of optional packages.
   - Add per-package CI for `jido_memory_mempalace` and `jido_memory_mem0`.
   - Acceptance: failures are isolated by package.

2. Dependency and release hygiene
   - Remove optional external deps from `jido_memory` where they only belong to downstream packages.
   - Keep `mix.exs` docs/dependency cleanups and maintain semantic versioning discipline.
   - Acceptance: core has minimal dependency blast radius.

3. Public stability checkpoints
   - Add a release checklist with:
     - compile and test across changed repos
     - provider contract coverage pass
     - docs/plan drift review
   - Acceptance: every release follows the same verification script.

## Ongoing Workstream for This Chat

Immediate execution order:
1. Finalize and execute Phase 1 validation hardening.
2. Draft `docs/provider_contract.md`.
3. Publish first `jido_memory_mempalace` provider package skeleton and callback tests.
4. Run migration-focused documentation pass in root README and contributor notes.

## Open Risks

- Full-suite tests in this environment may still fail due unrelated app startup issues in current container; track against CI behavior separately.
- Some behavior claims from early PR drafts may be ahead of current implemented surface; only advertise what is now covered by tests.
