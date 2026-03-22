# Canonical Memory Provider Architecture Plan

This planning set tracks the rollout of the canonical memory provider system in `jido_memory` as the unified Jido memory package with built-in provider choices.

## Phases
- `phase-01-provider-core-contract-and-basic-provider-backbone.md`
- `phase-02-capability-negotiation-and-provider-aware-runtime-facade.md`
- `phase-03-canonical-plugin-actions-and-compatibility-migration.md`
- `phase-04-native-tiered-provider-and-long-term-store.md`
- `phase-05-unified-documentation-release-and-built-in-provider-validation.md`

## Current Status
- Phases 1 through 5 are implemented on the current branch.
- Follow-on work is now limited to optional future external-provider interop and deeper advanced capabilities.
- The next planning set lives under `.spec/planning/provider_follow_ons/`.

## Delivery Rules
- `Jido.Memory.Runtime`, `recall/2`, `Jido.Memory.ETSPlugin`, and tuple-style public results stay compatible through the rollout.
- `Jido.Memory.Plugin` is the unified provider-aware plugin for core memory flows.
- `jido_memory` ships the standard built-in provider choices for Jido memory context management.
- `jido_memory_os` remains a standalone advanced library with its own native facade and plugin routes.
- Every phase ends with explicit integration coverage.
