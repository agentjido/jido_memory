# Phase 5 - Unified Documentation, Release, and Built-In Provider Validation

Description: finish the provider contract suite, documentation, release hardening, and built-in provider validation so `jido_memory` can ship as the unified Jido memory package.

## Section 5.1 - Built-In Provider Contract Suite and Fixtures
Description: keep the provider contract enforceable across the built-in provider matrix and make it easy to extend later.

### Task 5.1.1 - Expand reusable provider contract fixtures
Description: make provider contract coverage stable for the providers that now live inside `jido_memory`.
- [x] Extend the shared provider contract helper to cover Basic and Tiered.
- [x] Add fixture helpers for deterministic tier setup, long-term storage setup, and promotion-related record creation.
- [x] Keep the contract helper suitable for optional future external-provider testing without making that a release blocker.

### Task 5.1.2 - Add built-in provider acceptance scenarios
Description: validate the completed provider matrix from the point of view of a normal `jido_memory` consumer.
- [x] Verify a shared agent fixture can switch between built-in Basic and Tiered providers without changing common plugin code.
- [x] Verify `recall/2` and `retrieve/3` parity across the overlapping query subset for Basic and Tiered.
- [x] Verify Tiered reports supported lifecycle features where Basic reports unsupported capabilities.

## Section 5.2 - Documentation, Examples, and Migration Guides
Description: tell a clear story for choosing a built-in provider and understanding where `jido_memory_os` fits after the architecture change.

### Task 5.2.1 - Update `jido_memory` docs and examples
Description: document `jido_memory` as the unified entrypoint for standard Jido memory context management.
- [x] Update README and guides to show `Jido.Memory.Plugin` with built-in Basic and Tiered provider configuration.
- [x] Document the compatibility guarantees for `Runtime`, `recall/2`, `ETSPlugin`, and tuple-style public results.
- [x] Add examples that show how to switch the same agent from Basic to Tiered.

### Task 5.2.2 - Clarify the `jido_memory_os` boundary
Description: document the relationship between the unified core package and the standalone advanced library without making the latter a required dependency.
- [x] Document that `jido_memory_os` remains a standalone advanced library with its native facade and plugin.
- [x] Explain when to choose built-in Tiered in `jido_memory` versus native `jido_memory_os` workflows.
- [x] Defer optional provider-interop documentation until the built-in provider story is stable.

## Section 5.3 - Release and Acceptance Hardening
Description: align the built-in provider story with release expectations and final quality gates.

### Task 5.3.1 - Lock release readiness for `jido_memory`
Description: make the core package releasable with the new built-in provider matrix.
- [x] Run the full `jido_memory` quality gates against the provider-enabled implementation.
- [x] Add release notes covering the provider system, built-in provider choices, and the standalone `jido_memory_os` boundary.
- [x] Ensure package docs and examples describe the tested provider configuration model.

### Task 5.3.2 - Keep follow-on work explicit
Description: prevent optional external-provider interop from being confused with the built-in provider release criteria.
- [x] Mark external-provider interop as follow-on work rather than a blocker for shipping built-in Tiered support.
- [x] Keep any future `jido_memory_os` provider bridge out of the release-critical path unless explicitly re-scoped later.
- [x] Capture remaining open questions about long-term persistence, explainability depth, and external-provider ergonomics.

## Section 5.4 - Phase 5 Integration Tests
Description: validate the completed built-in provider architecture, docs-backed examples, and release expectations end to end.

### Task 5.4.1 - Cross-provider runtime and plugin scenarios
Description: verify the completed architecture from the consumer point of view.
- [x] Verify the same core memory workflow succeeds through `Jido.Memory.Plugin` when backed by Basic and when backed by Tiered.
- [x] Verify `Jido.Memory.Runtime` advanced helpers return unsupported results under Basic and real lifecycle results under Tiered.
- [x] Verify docs-backed examples execute against the tested built-in provider configurations.

### Task 5.4.2 - Release and migration acceptance scenarios
Description: verify the implementation is safe to publish and safe to adopt incrementally.
- [x] Verify existing `jido_memory` consumers can upgrade without changing current runtime or `ETSPlugin` call sites.
- [x] Verify new consumers can select Tiered through the canonical provider config with no custom plugin code.
- [x] Verify the published documentation matches the tested built-in provider selection model and the standalone `jido_memory_os` boundary.

## Completion Notes

- The release-critical built-in provider matrix is now `:basic` and `:tiered`.
- `jido_memory_os` remains documented as a standalone advanced library.
- Optional external-provider interop is follow-on work rather than a blocker for shipping this architecture.
