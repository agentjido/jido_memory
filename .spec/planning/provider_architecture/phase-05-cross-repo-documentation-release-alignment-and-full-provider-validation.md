# Phase 5 - Cross-Repo Documentation, Release Alignment, and Full Provider Validation

Description: finish the shared contract suite, docs, release alignment, and cross-provider validation.

## Section 5.1 - Shared Provider Contract Suite and Fixtures
Description: keep provider contract coverage stable across repositories.
- [x] Add a reusable `Jido.Memory.ProviderContract` helper in `jido_memory`.
- [x] Reuse that helper in `jido_memory` and `jido_memory_os` provider tests.
- [ ] Add more fixture helpers if additional providers join the matrix.

## Section 5.2 - Documentation, Examples, and Migration Guides
Description: ship a clear story for selecting providers and understanding compatibility.
- [ ] Update `jido_memory` README/examples for Basic and MemoryOS providers.
- [ ] Update `jido_memory_os` README/examples for `Jido.Memory.Plugin` with `Jido.MemoryOS.Provider`.
- [ ] Document the split between the common plugin and the native MemoryOS plugin.

## Section 5.3 - Release and Acceptance Hardening
Description: align dependency boundaries and rollout expectations across repos.
- [x] Align `jido_memory_os` dev/test dependency resolution with the provider-enabled `jido_memory` workspace.
- [ ] Pin the final supported ref/version pair once the upstream `jido_memory` changes are committed and published.
- [ ] Run the full repo suites and resolve any remaining regressions.

## Section 5.4 - Phase 5 Integration Tests
Description: validate the completed cross-provider architecture end to end.
- [ ] Run the full `jido_memory` suite under the provider-enabled implementation.
- [ ] Run the full `jido_memory_os` suite against the aligned dependency set.
- [ ] Confirm docs and examples match the tested configuration model.
