# Phase 3 - Durable Long-Term Store Backends and Ops Guides

Description: move the long-term persistence story beyond the default ETS implementation so Tiered can support durable deployments with clear operational guidance.

## Section 3.1 - Durable Long-Term Backend Contracts
Description: stabilize the long-term store seam for real persistence backends.

### Task 3.1.1 - Tighten long-term store behavior expectations
Description: make the `Jido.Memory.LongTermStore` boundary explicit enough for durable backends to implement confidently.
- [ ] Document required semantics for idempotency, delete behavior, query support, and prune support.
- [ ] Clarify which long-term operations must preserve record shape and provider-managed metadata.
- [ ] Decide what minimum query subset a durable backend must support to be considered production-ready.

### Task 3.1.2 - Add durable backend test fixtures
Description: create reusable fixtures that exercise long-term store behavior independently of a specific database.
- [ ] Add a shared long-term store contract helper for backend tests.
- [ ] Add fixture coverage for durable read/write/query/forget/prune behavior.
- [ ] Keep the contract helper usable by first-party and third-party long-term backends.

## Section 3.2 - First Durable Backend Path
Description: establish one real durable backend path that proves the seam is practical.

### Task 3.2.1 - Choose the first supported durable backend
Description: pick the first serious long-term backend based on fit, maintainability, and user value.
- [ ] Evaluate Postgres and Redis against the current long-term store contract.
- [ ] Select the first backend to implement or officially document as the reference durable path.
- [ ] Capture the tradeoffs that justify the choice, including query capabilities and operational complexity.

### Task 3.2.2 - Implement the first durable backend
Description: add or split out a concrete long-term store implementation that can back Tiered in durable environments.
- [ ] Implement the chosen durable backend behind `Jido.Memory.LongTermStore`.
- [ ] Add configuration docs and validation for the backend.
- [ ] Keep the default ETS long-term path intact for local and test use.

## Section 3.3 - Operational Docs and Deployment Guidance
Description: document how to run Tiered with durable long-term persistence in real applications.

### Task 3.3.1 - Add operational guides for long-term persistence
Description: give users a concrete path from local ETS usage to durable deployment.
- [ ] Add guides for selecting and configuring a durable long-term backend.
- [ ] Document migration considerations from ETS long-term storage to a durable backend.
- [ ] Explain durability, consistency, and pruning tradeoffs clearly.

### Task 3.3.2 - Clarify support boundaries
Description: keep the initial durable-backend story focused and supportable.
- [ ] Mark additional durable backends as follow-on work until the first backend path is stable.
- [ ] Keep unsupported backend features explicit rather than implying full parity.
- [ ] Capture open questions around pagination, indexing, and backend-native querying.

## Section 3.4 - Phase 3 Integration Tests
Description: validate that durable long-term storage works end to end through Tiered.

### Task 3.4.1 - Long-term store contract scenarios
Description: prove durable backends satisfy the long-term store seam consistently.
- [ ] Verify the shared long-term store contract passes for ETS and the first durable backend.
- [ ] Verify durable backend queries return the same overlapping result subset as the ETS implementation.
- [ ] Verify prune and forget semantics remain stable across long-term backends.

### Task 3.4.2 - Tiered over durable storage scenarios
Description: prove Tiered can use durable long-term persistence without changing the common plugin or runtime API.
- [ ] Verify Tiered promotion from mid to long works against the durable long-term backend.
- [ ] Verify retrieval across short, mid, and durable long-term layers works through the provider-aware runtime.
- [ ] Verify operational guide examples execute against the tested durable backend configuration.
