# Phase 2 - Capability Negotiation and Provider-Aware Runtime Facade

Description: add optional capability behaviours, structured capability discovery, compatibility-first error normalization, and the expanded runtime facade.

## Section 2.1 - Optional Capability Behaviours and Helpers
Description: define optional provider contracts and capability inspection helpers.

### Task 2.1.1 - Introduce optional capability behaviours
Description: freeze the advanced provider callback families before downstream implementations.
- [x] Add `Jido.Memory.Capability.Lifecycle` with `consolidate/2`.
- [x] Add `Jido.Memory.Capability.ExplainableRetrieval` with `explain_retrieval/3`.
- [x] Add `Operations`, `Governance`, and `TurnHooks` behaviours.

### Task 2.1.2 - Introduce capability discovery helpers
Description: standardize capability maps so runtime and tests can reason about support.
- [x] Add `Jido.Memory.Capabilities` normalization helpers.
- [x] Standardize structured capability metadata.
- [x] Add support checks for lifecycle, explainability, and operations paths.

## Section 2.2 - Error Normalization and Capability Dispatch
Description: introduce provider-layer error concepts without breaking current callers.

### Task 2.2.1 - Add provider-layer errors and normalization rules
Description: define internal provider errors while keeping public tuple-style results.
- [x] Add `Jido.Memory.Error.UnsupportedCapability`.
- [x] Add `Jido.Memory.Error.InvalidProvider`.
- [x] Normalize provider/bootstrap failures through the runtime boundary.

### Task 2.2.2 - Add capability-gated dispatch helpers
Description: centralize advanced capability invocation and rejection.
- [x] Inspect capability metadata before advanced dispatch.
- [x] Return unsupported-capability failures through one path.
- [x] Keep provider metadata available to `info/3` and `capabilities/2`.

## Section 2.3 - Expanded Runtime Facade
Description: expose the new canonical runtime helpers while preserving compatibility calls.
- [x] Add `retrieve/3` and delegate `recall/2` to it.
- [x] Add `capabilities/2` and `info/3`.
- [x] Add capability-gated `consolidate/2` and `explain_retrieval/3`.
- [x] Keep provider-direct Operations and Governance callbacks out of the v1 facade.

## Section 2.4 - Phase 2 Integration Tests
Description: validate capability discovery and the advanced runtime facade against Basic.
- [x] Verify Basic reports core-only capabilities.
- [x] Verify `retrieve/3` and `recall/2` parity.
- [x] Verify unsupported capability failures remain deterministic.
