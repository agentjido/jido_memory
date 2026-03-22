# Phase 1 - External Provider Interop and Bootstrap Seams

Description: extend the provider architecture so external memory implementations can plug into `jido_memory` cleanly without weakening the built-in provider story.

## Section 1.1 - External Provider Selection and Registration
Description: define the explicit boundary between built-in providers and optional external providers.

### Task 1.1.1 - Formalize external provider selection rules
Description: make external provider selection predictable for runtime calls, plugin state, and release docs.
- [x] Define and document how built-in aliases, direct modules, and external tuples are resolved.
- [x] Keep invalid external provider failures deterministic and compatibility-safe at the runtime boundary.
- [x] Prevent ambiguous provider precedence between runtime opts, plugin state, and provider defaults.

### Task 1.1.2 - Add optional provider registration helpers
Description: provide a small ergonomic layer for libraries that want to advertise provider modules without making registration mandatory.
- [x] Decide whether provider registration is config-driven, module-driven, or helper-only.
- [x] Add helper APIs for provider discovery and validation that external packages can reuse.
- [x] Keep direct tuple and module provider selection working even when no registry is configured.

## Section 1.2 - Provider Bootstrap and Runtime Ownership
Description: clarify how external providers participate in initialization and optional supervised startup.

### Task 1.2.1 - Define provider bootstrap ownership
Description: resolve how `child_specs/1` and `init/1` should be used when providers require runtime processes.
- [x] Document the intended use of `child_specs/1` for external providers that need supervision.
- [x] Decide whether `Jido.Memory.Plugin` should remain process-neutral or gain optional provider bootstrap hooks.
- [x] Keep built-in Basic and Tiered startup behavior unchanged unless explicit provider bootstrap is configured.

### Task 1.2.2 - Add external-provider fixture coverage
Description: create a small, fake external provider implementation inside tests so interop rules are exercised without adding a real external dependency.
- [x] Add a minimal external provider fixture that satisfies the core provider contract.
- [x] Use the fixture to test provider resolution, capability discovery, and info lookups.
- [x] Keep the fixture suitable for future package-level contract reuse.

## Section 1.3 - Interop Documentation and Migration Boundaries
Description: document what `jido_memory` guarantees to external provider authors and what remains explicitly out of scope.

### Task 1.3.1 - Publish external-provider authoring guidance
Description: explain how another library can satisfy the canonical provider contract without relying on built-in internals.
- [ ] Add a guide for implementing `Jido.Memory.Provider` in an external package.
- [ ] Document required versus optional capability behaviors for interop.
- [ ] Explain how external providers should normalize errors for compatibility callers.

### Task 1.3.2 - Clarify the `jido_memory_os` interop boundary
Description: keep optional MemoryOS interop from being confused with a required dependency.
- [ ] Document `jido_memory_os` as one possible external provider candidate rather than a built-in path.
- [ ] Keep MemoryOS-specific bootstrap, manager ownership, and plugin flows outside the core release-critical path.
- [ ] Capture any remaining open questions about provider bootstrap ownership before implementation begins.

## Section 1.4 - Phase 1 Integration Tests
Description: validate that external-provider interop is real and safe without regressing built-in provider behavior.

### Task 1.4.1 - Provider resolution scenarios
Description: prove built-in and external provider selection rules are deterministic.
- [ ] Verify the same runtime and plugin path can target a built-in provider or a test external provider through canonical config.
- [ ] Verify invalid external providers fail before dispatch with compatibility-safe runtime errors.
- [ ] Verify capability discovery and provider info remain stable across built-in and external providers.

### Task 1.4.2 - Bootstrap and migration scenarios
Description: prove optional interop does not destabilize the built-in path.
- [ ] Verify built-in Basic and Tiered behavior remains unchanged when no external provider bootstrap is configured.
- [ ] Verify external provider bootstrap helpers behave predictably when providers expose child specs.
- [ ] Verify external-provider documentation examples align with tested selection and bootstrap behavior.
