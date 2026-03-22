# Provider Follow-On Plan

This planning set tracks the next wave of work after the built-in provider rollout in `jido_memory`.

## Summary
- Keep the completed built-in provider architecture stable while opening deliberate seams for optional external providers.
- Deepen the built-in Tiered provider with explainability and lifecycle inspection rather than only CRUD and consolidation.
- Add durable long-term storage paths beyond ETS without making any one backend mandatory for all users.

## Phases
- `phase-01-external-provider-interop-and-bootstrap-seams.md`
- `phase-02-tiered-explainability-and-lifecycle-inspection.md`
- `phase-03-durable-long-term-store-backends-and-ops-guides.md`
- `phase-04-release-hardening-and-follow-on-acceptance.md`

## Current Status
- Phase 1 is implemented on the current branch.
- Phase 2 is implemented on the current branch.
- Phase 3 is implemented on the current branch.
- Phase 4 is implemented on the current branch.

## Delivery Rules
- `Jido.Memory.Runtime`, `recall/2`, `Jido.Memory.ETSPlugin`, and tuple-style public results stay compatible.
- Built-in `:basic` and `:tiered` remain the release-critical defaults while external-provider interop stays opt-in.
- `jido_memory_os` remains a standalone advanced library unless explicitly re-scoped later.
- Every phase ends with explicit integration coverage.
