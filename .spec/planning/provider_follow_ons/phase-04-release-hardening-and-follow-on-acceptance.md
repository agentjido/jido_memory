# Phase 4 - Release Hardening and Follow-On Acceptance

Description: close the loop on the follow-on work so external-provider interop, Tiered explainability, and durable long-term persistence can ship with clear quality gates and documentation.

## Section 4.1 - Cross-Capability Acceptance Matrix
Description: validate the combined architecture after the follow-on phases land.

### Task 4.1.1 - Define the follow-on acceptance matrix
Description: make the supported combinations of providers, capabilities, and long-term backends explicit.
- [x] Define the tested matrix for built-in Basic, built-in Tiered, and the external-provider reference path.
- [x] Define the tested matrix for ETS and the first durable long-term backend.
- [x] Keep unsupported combinations explicit rather than inferred.

### Task 4.1.2 - Add end-to-end acceptance fixtures
Description: provide a consumer-level test path that exercises the combined architecture.
- [x] Add end-to-end fixtures that mount the common plugin against built-in and external providers.
- [x] Include Tiered explainability and durable long-term promotion in the acceptance flow.
- [x] Keep the fixture paths suitable for release gating and documentation examples.

## Section 4.2 - Documentation and Release Narrative
Description: tell one coherent story for users choosing between built-in and optional paths.

### Task 4.2.1 - Publish the follow-on user and developer docs
Description: explain how the expanded provider system should be adopted after the initial rollout.
- [x] Update guides and README sections to cover external-provider interop, Tiered explainability, and durable long-term backends.
- [x] Clarify when to stay with built-in Tiered versus when to adopt an external provider or `jido_memory_os`.
- [x] Keep the migration story incremental and compatibility-first.

### Task 4.2.2 - Add release notes and known limits
Description: make the shipped scope explicit so support expectations stay realistic.
- [x] Add release notes for the new interop, explainability, and durable-backend capabilities.
- [x] Document any known limits around bootstrap ownership, explanation depth, and backend query parity.
- [x] Capture the next open questions that should become their own planning set rather than leaking into this one.

## Section 4.3 - Quality Gates and Tooling Alignment
Description: keep the release gate trustworthy as the provider system grows more capable.

### Task 4.3.1 - Align CI and local quality gates
Description: make the final release gate reflect the actual supported architecture.
- [x] Ensure `mix quality` covers the intended acceptance suite for the expanded provider matrix.
- [x] Keep spec verification, docs examples, and backend contract tests in the release path.
- [x] Prevent optional or experimental provider paths from blocking the supported release matrix.

### Task 4.3.2 - Freeze the follow-on release criteria
Description: turn the expanded architecture into a shippable, supportable package boundary.
- [x] Require all built-in provider tests to pass unchanged.
- [x] Require the external-provider reference path and first durable backend path to pass their contract suites.
- [x] Require the published documentation to match the tested provider and backend configuration story.

## Section 4.4 - Phase 4 Integration Tests
Description: validate the full follow-on architecture from the point of view of a real consumer.

### Task 4.4.1 - Cross-provider and cross-backend scenarios
Description: prove the common plugin and runtime can span the supported matrix cleanly.
- [x] Verify the same core memory workflow succeeds with built-in Basic, built-in Tiered, and the external-provider reference path.
- [x] Verify Tiered explainability and durable long-term promotion remain correct under the accepted backend matrix.
- [x] Verify unsupported capabilities still fail cleanly outside the supported matrix.

### Task 4.4.2 - Release and migration scenarios
Description: prove the follow-on work is safe to ship and safe to adopt incrementally.
- [x] Verify existing `jido_memory` consumers can keep using built-in Basic or Tiered without opting into external-provider interop.
- [x] Verify new consumers can add explainability or durable long-term storage without changing the common plugin contract.
- [x] Verify published guides and release notes match the tested follow-on architecture.
