# Provider Benchmarking Plan

This planning set tracks benchmark work for the built-in provider matrix and the
external-provider reference path in `jido_memory`.

## Summary

<!-- covers: jido_memory.matrix.benchmarking.shared_overlap_first -->
<!-- covers: jido_memory.matrix.benchmarking.provider_specific_lane -->
<!-- covers: jido_memory.matrix.benchmarking.reproducible_fixtures -->
<!-- covers: jido_memory.matrix.benchmarking.results_inform_but_do_not_redefine_core -->
- Add a reproducible benchmark harness that compares overlapping canonical memory
  flows across `:basic`, `:tiered`, `:mirix`, and the external-provider reference
  path.
- Keep provider-specific advanced benchmark packs explicit so MIRIX ingestion,
  MIRIX vault isolation, Tiered lifecycle, and durable long-term storage checks do
  not redefine the required common facade.
- Use benchmark output to guide future core changes only after the results prove a
  cross-provider pattern is reusable.

## Phases
- `phase-01-benchmark-contract-and-fixture-boundary.md`
- `phase-02-shared-harness-and-metric-capture.md`
- `phase-03-provider-specific-scenario-packs.md`
- `phase-04-reporting-and-release-gated-benchmark-runs.md`

## Current Status
- Phase 1 is pending.
- Phase 2 is pending.
- Phase 3 is pending.
- Phase 4 is pending.

## Delivery Rules
- Shared benchmark runs start with overlapping canonical flows only.
- Provider-specific benchmark packs stay separate from the cross-provider shared
  matrix.
- Default benchmark runs avoid mandatory external services.
- Every phase ends with explicit integration-style benchmark coverage or dry-run
  verification.
