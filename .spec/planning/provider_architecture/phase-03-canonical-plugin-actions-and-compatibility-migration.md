# Phase 3 - Canonical Plugin, Actions, and Compatibility Migration

Description: add the provider-aware common plugin and action surface while preserving `ETSPlugin`, `Recall`, and existing config shapes.

## Section 3.1 - Canonical Provider-Aware Plugin
Description: make the common plugin the cross-provider entrypoint for core memory operations.

### Task 3.1.1 - Introduce `Jido.Memory.Plugin`
Description: accept explicit provider bundles while preserving the current default experience.
- [x] Add `Jido.Memory.Plugin`.
- [x] Accept canonical `provider: {module, opts}` configuration.
- [x] Persist normalized provider references in plugin state.

### Task 3.1.2 - Preserve `ETSPlugin` compatibility
Description: keep current plugin consumers working with no required config rewrite.
- [x] Keep `Jido.Memory.ETSPlugin` as a compatibility wrapper.
- [x] Preserve the `:__memory__` state key and auto-capture defaults.
- [x] Map legacy top-level plugin config into the Basic provider bundle.

## Section 3.2 - Action and Route Alignment
Description: add canonical retrieve naming while preserving recall compatibility.
- [x] Add `Jido.Memory.Actions.Retrieve`.
- [x] Keep `Jido.Memory.Actions.Recall` as a compatibility wrapper.
- [x] Expose both `retrieve` and `recall` routes.
- [x] Route actions through the provider-aware runtime facade.

## Section 3.3 - Plugin State and Config Compatibility Hardening
Description: keep old and new config styles interoperable and preserve checkpoint/restore behavior.
- [x] Normalize provider-aware and legacy plugin state.
- [x] Keep checkpoint/restore deterministic.
- [x] Ensure auto-capture writes through the configured provider path.

## Section 3.4 - Phase 3 Integration Tests
Description: validate plugin mounting, action routing, auto-capture, and compatibility handling.
- [x] Cover `Jido.Memory.Plugin` default and explicit provider mounts.
- [x] Verify `ETSPlugin` behavior remains stable.
- [x] Verify `Recall` and `Retrieve` both succeed against the same records.
