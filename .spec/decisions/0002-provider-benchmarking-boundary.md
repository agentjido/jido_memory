---
id: jido_memory.provider_benchmarking_boundary
status: accepted
date: 2026-03-22
affects:
  - jido_memory.matrix.benchmarking
---

# ADR 0002: Provider Benchmarking Boundary

## Context

`jido_memory` now ships multiple built-in provider choices with different internal
tradeoffs:

- `:basic` for the smallest canonical core path
- `:tiered` for lifecycle-oriented promotion and long-term persistence
- `:mirix` for routed memory types, active retrieval explainability, provider-direct
  ingestion, and protected memory

That creates a new risk: benchmark work can accidentally compare providers on
non-overlapping features, or it can pressure the canonical runtime and plugin
surfaces to grow around whichever provider has the richest implementation.

We want benchmark work to help evaluate the architecture without redefining the
architecture.

## Decision

<!-- covers: jido_memory.matrix.benchmarking.shared_overlap_first -->
<!-- covers: jido_memory.matrix.benchmarking.provider_specific_lane -->
<!-- covers: jido_memory.matrix.benchmarking.reproducible_fixtures -->
<!-- covers: jido_memory.matrix.benchmarking.results_inform_but_do_not_redefine_core -->

Benchmarking in `jido_memory` will follow four rules:

1. Shared benchmark runs compare overlapping canonical flows first.
2. Provider-specific benchmark scenarios are tracked separately from the shared
   cross-provider matrix.
3. Benchmark fixtures and datasets are reproducible, repository-owned, and safe to
   run without external services by default.
4. Benchmark results inform future provider and facade decisions, but they do not
   widen the canonical core automatically.

## Consequences

### Positive

- Benchmark output stays aligned with the provider contract and the shared plugin
  and runtime surface.
- `:basic`, `:tiered`, `:mirix`, and the external-provider reference path can be
  compared fairly on overlapping capabilities.
- Advanced provider features such as MIRIX ingestion or vault workflows can still
  be evaluated without pretending they are part of the required common facade.

### Tradeoffs

- The benchmark harness needs both shared scenarios and provider-specific scenario
  packs.
- Some advanced provider comparisons will remain asymmetric by design.
- Release gating should be conservative until benchmark runs are stable and
  affordable.

## Notes

This ADR defines the benchmark boundary only. It does not claim that a benchmark
harness, fixtures, or reports have been implemented yet.
