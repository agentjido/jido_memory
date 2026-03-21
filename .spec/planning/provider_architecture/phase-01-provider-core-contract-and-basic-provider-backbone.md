# Phase 1 - Provider Core Contract and Basic Provider Backbone

Description: introduce the core provider contract, provider normalization, and the default Basic provider without breaking current runtime flows.

## Section 1.1 - Provider Contract and Reference Normalization
Description: define the minimum provider interface and the normalized provider bundle representation.

### Task 1.1.1 - Introduce the provider core behaviour
Description: add the canonical callback surface used by all providers.
- [x] Create `Jido.Memory.Provider` with `validate_config/1`, `child_specs/1`, `init/1`, `capabilities/1`, `remember/3`, `get/3`, `retrieve/3`, `forget/3`, `prune/2`, and `info/2`.
- [x] Define provider metadata and provider opts types.
- [x] Document `retrieve/3` as the canonical internal read operation.

### Task 1.1.2 - Introduce provider reference normalization
Description: make provider selection deterministic for runtime calls, plugin state, and defaults.
- [x] Add `Jido.Memory.ProviderRef`.
- [x] Validate required callbacks before dispatch.
- [x] Default to `Jido.Memory.Provider.Basic` when no provider is configured.

## Section 1.2 - Basic Provider Extraction
Description: move the existing store-backed runtime logic into the Basic provider.

### Task 1.2.1 - Extract current runtime logic into `Jido.Memory.Provider.Basic`
Description: keep namespace, store, record, and query behavior stable behind the provider boundary.
- [x] Move remember/get/retrieve/forget/prune flow into `Basic`.
- [x] Keep `Jido.Memory.Store` and `Jido.Memory.Store.ETS` unchanged.
- [x] Expose core-only capabilities and minimal metadata from `Basic`.

### Task 1.2.2 - Define Basic provider bootstrap semantics
Description: lock the config validation and metadata shape for the default provider.
- [x] Accept current store and namespace config shape in `validate_config/1`.
- [x] Return no child specs from `child_specs/1`.
- [x] Expose store defaults and capability metadata from `init/1` and `info/2`.

## Section 1.3 - Runtime Internal Dispatch Backbone
Description: make `Jido.Memory.Runtime` provider-aware internally while keeping public entrypoints stable.

### Task 1.3.1 - Route current runtime functions through provider dispatch
Description: preserve the public API while removing direct store-only assumptions from the facade.
- [x] Route `remember/3`, `get/3`, `forget/3`, `recall/2`, and `prune_expired/2` through provider callbacks.
- [x] Keep `namespace`, `store`, and `store_opts` working through Basic-provider mapping.
- [x] Preserve plugin-state inference.

### Task 1.3.2 - Preserve compatibility invariants
Description: keep the package contract stable for users who do not opt into providers explicitly.
- [x] Keep `Jido.Memory.Runtime` as the main public entrypoint.
- [x] Preserve existing invalid-input error atoms for current flows.
- [x] Keep the legacy tests green without plugin/action changes.

## Section 1.4 - Phase 1 Integration Tests
Description: validate the new provider contract and the Basic provider end to end.
- [x] Add direct provider contract coverage for `Basic`.
- [x] Verify invalid provider references fail before dispatch.
- [x] Verify runtime parity for explicit store/namespace paths and plugin-state inference.
