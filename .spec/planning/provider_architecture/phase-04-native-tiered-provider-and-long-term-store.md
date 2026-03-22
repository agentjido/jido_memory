# Phase 4 - Native Tiered Provider and Long-Term Store

Description: implement a built-in Tiered provider in `jido_memory` that brings short, mid, and long memory principles into the core package without importing the full MemoryOS control plane.

## Section 4.1 - Tiered Provider Module and Unified Configuration
Description: add the built-in Tiered provider and make it selectable through the same provider-aware runtime and plugin surface that already powers Basic.

### Task 4.1.1 - Introduce `Jido.Memory.Provider.Tiered`
Description: define the built-in Tiered provider as the standard advanced provider choice shipped by `jido_memory`.
- [ ] Create `Jido.Memory.Provider.Tiered` implementing `Jido.Memory.Provider`.
- [ ] Add a stable built-in provider selection path for Tiered through `Jido.Memory.ProviderRef` and plugin configuration.
- [ ] Return Tiered-specific provider metadata and structured capability data from `init/1` and `capabilities/1`.

### Task 4.1.2 - Define Tiered provider configuration
Description: make the built-in Tiered provider configurable without forcing callers to assemble low-level details in agent code.
- [ ] Define provider config for short, mid, and long storage plus lifecycle policy options.
- [ ] Provide sensible defaults so Tiered works out of the box with ETS-backed stores in development.
- [ ] Validate tier, promotion, and consolidation settings through the provider config boundary.

## Section 4.2 - Tier Lifecycle, Retrieval, and Long-Term Persistence
Description: implement the core tiered-memory behaviors that belong inside `jido_memory`.

### Task 4.2.1 - Add long-term persistence and tier transitions
Description: make the Tiered provider capable of moving records between memory layers while keeping persistence pluggable.
- [ ] Introduce a long-term persistence behaviour or equivalent abstraction suitable for the Tiered provider.
- [ ] Provide a default ETS-backed long-term implementation for the built-in path.
- [ ] Implement promotion and consolidation flows across short, mid, and long tiers.

### Task 4.2.2 - Add cross-tier retrieval and lifecycle-aware metadata
Description: make retrieval and lifecycle reasoning consistent across the tiered memory surface.
- [ ] Implement retrieval across one or more tiers through the provider `retrieve/3` callback.
- [ ] Add provider-managed metadata needed to explain tier placement, promotion decisions, and consolidation outcomes.
- [ ] Expose lifecycle and retrieval capability metadata in a way the common runtime can inspect.

## Section 4.3 - Runtime, Plugin, and Compatibility Integration
Description: wire the built-in Tiered provider into the existing common facade without breaking the already-landed Basic path.

### Task 4.3.1 - Integrate Tiered with `Jido.Memory.Runtime`
Description: keep the runtime facade stable while letting callers choose Tiered through the provider system.
- [ ] Route Tiered provider selection cleanly through existing provider normalization.
- [ ] Preserve the current compatibility behavior for Basic when no provider is specified.
- [ ] Keep unsupported-capability behavior deterministic for providers that are still core-only.

### Task 4.3.2 - Integrate Tiered with `Jido.Memory.Plugin` and actions
Description: ensure the common agent-facing plugin and action API can switch from Basic to Tiered without changing call sites.
- [ ] Make `Jido.Memory.Plugin` mount cleanly with the built-in Tiered provider.
- [ ] Keep `Remember`, `Retrieve`, `Recall`, and `Forget` action behavior stable across Basic and Tiered.
- [ ] Preserve checkpoint, restore, and auto-capture behavior through the Tiered provider path.

## Section 4.4 - Phase 4 Integration Tests
Description: validate that Tiered is a real built-in provider choice rather than a special case outside the common architecture.

### Task 4.4.1 - Tiered provider contract scenarios
Description: prove the new built-in provider satisfies the same shared contract as Basic.
- [ ] Verify `Jido.Memory.Provider.Tiered` passes the shared provider contract suite.
- [ ] Verify Tiered reports lifecycle and retrieval capability metadata through the standard capability map.
- [ ] Verify invalid Tiered configuration fails deterministically at the provider boundary.

### Task 4.4.2 - Tiered runtime and plugin scenarios
Description: prove the common runtime and plugin can use Tiered end to end.
- [ ] Verify the same agent fixture can switch between Basic and Tiered without changing common plugin code.
- [ ] Verify Tiered promotion, consolidation, and long-term persistence behavior through the provider-aware runtime surface.
- [ ] Verify `Retrieve` and `Recall` remain compatible against Tiered-backed records.
