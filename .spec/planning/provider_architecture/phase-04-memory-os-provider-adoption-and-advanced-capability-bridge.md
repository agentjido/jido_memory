# Phase 4 - MemoryOS Provider Adoption and Advanced Capability Bridge

Description: implement `Jido.MemoryOS.Provider`, bridge MemoryOS internals to the canonical provider contract, and expose the intended advanced capabilities through the shared facade.

## Section 4.1 - MemoryOS Provider Module and Bootstrap
Description: add the provider module in `jido_memory_os` and align its bootstrap model with the shared contract.
- [x] Add `Jido.MemoryOS.Provider` implementing `Jido.Memory.Provider`.
- [x] Validate MemoryOS config and framework adapter defaults through provider opts.
- [x] Surface `MemoryManager` child specs and provider metadata.

## Section 4.2 - Capability Implementations and Error Bridge
Description: map MemoryOS features to the canonical capability behaviours and normalize provider-facing errors.
- [x] Implement lifecycle and explainable retrieval capabilities.
- [x] Implement Operations, Governance, and TurnHooks callbacks.
- [x] Normalize common provider-facing validation/runtime reasons where compatibility matters.
- [x] Sanitize common-plugin state before delegating into MemoryOS internals to avoid recursive provider re-entry.

## Section 4.3 - Common Plugin Interoperability and Dependency Alignment
Description: make the shared plugin able to target MemoryOS for core flows while keeping `Jido.MemoryOS.Plugin` for advanced routes.
- [x] Align `jido_memory_os` with the provider-enabled `jido_memory` dependency set.
- [x] Verify `Jido.Memory.Plugin` can mount with `provider: {Jido.MemoryOS.Provider, opts}`.
- [x] Keep `Jido.MemoryOS.Plugin` unchanged for MemoryOS-specific framework adapter flows.

## Section 4.4 - Phase 4 Integration Tests
Description: validate that MemoryOS satisfies the provider contract and works through both the common runtime and the common plugin.
- [x] Add a dedicated MemoryOS provider integration phase.
- [x] Verify `Runtime.consolidate/2` and `Runtime.explain_retrieval/3` work when MemoryOS is selected.
- [x] Verify provider-direct operations, governance, and turn hooks execute successfully.
- [x] Verify `Jido.Memory.Plugin` over MemoryOS preserves `Retrieve` and `Recall` compatibility.
