# Benchmarking Matrix

This subject defines the draft benchmark boundary for comparing built-in and
external memory providers without distorting the canonical core contract.

## Intent

Benchmark overlapping canonical behavior fairly, keep provider-specific scenarios
explicit, and treat benchmark output as input to architectural decisions rather
than an excuse to widen shared APIs prematurely.

```spec-meta
id: jido_memory.matrix.benchmarking
kind: architecture
status: draft
summary: Draft matrix for cross-provider benchmarking, provider-specific scenario packs, and benchmark result boundaries.
surface:
  - .spec/decisions/0002-provider-benchmarking-boundary.md
  - .spec/planning/provider_benchmarking/*.md
decisions:
  - jido_memory.provider_benchmarking_boundary
```

## Requirements

```spec-requirements
- id: jido_memory.matrix.benchmarking.shared_overlap_first
  statement: Cross-provider benchmark runs shall compare overlapping canonical memory flows before comparing provider-specific advanced features.
  priority: must
  stability: evolving
- id: jido_memory.matrix.benchmarking.provider_specific_lane
  statement: Provider-specific benchmark scenarios shall be tracked separately from the shared cross-provider benchmark matrix so advanced features do not redefine the required common facade.
  priority: must
  stability: evolving
- id: jido_memory.matrix.benchmarking.reproducible_fixtures
  statement: Planned benchmark fixtures and datasets shall be repository-owned, reproducible, and runnable without external services by default, with optional durable-backend or provider-direct extensions layered on deliberately.
  priority: must
  stability: evolving
- id: jido_memory.matrix.benchmarking.results_inform_but_do_not_redefine_core
  statement: Benchmark outputs shall inform future provider and facade decisions, but they shall not widen the canonical runtime, plugin, or required provider contract automatically.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: jido_memory.matrix.benchmarking.shared_provider_matrix_path
  given:
    - a benchmark run that compares built-in `:basic`, built-in `:tiered`, built-in `:mirix`, built-in `:mem0`, and the external-provider reference path
  when:
    - the run evaluates canonical remember, retrieve, recall, explainability, and provider selection flows that overlap across those paths
  then:
    - the benchmark focuses on comparable shared behavior before any provider-specific advanced scenarios are considered
  covers:
    - jido_memory.matrix.benchmarking.shared_overlap_first
- id: jido_memory.matrix.benchmarking.provider_specific_advanced_path
  given:
    - a benchmark run that includes MIRIX ingestion and vault isolation, Tiered lifecycle and durable long-term promotion, or Mem0 extraction-and-reconciliation maintenance and graph-augmented explanation paths
  when:
    - those scenarios are evaluated alongside the shared provider matrix
  then:
    - they are recorded as provider-specific benchmark packs rather than treated as new required common-surface obligations
  covers:
    - jido_memory.matrix.benchmarking.provider_specific_lane
    - jido_memory.matrix.benchmarking.results_inform_but_do_not_redefine_core
- id: jido_memory.matrix.benchmarking.reproducible_local_path
  given:
    - a repository-owned benchmark fixture set
  when:
    - benchmark runs are executed in the default local development environment
  then:
    - the default path avoids mandatory external services and keeps durable-backend or provider-direct expansions opt-in
  covers:
    - jido_memory.matrix.benchmarking.reproducible_fixtures
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/0002-provider-benchmarking-boundary.md
  covers:
    - jido_memory.matrix.benchmarking.shared_overlap_first
    - jido_memory.matrix.benchmarking.provider_specific_lane
    - jido_memory.matrix.benchmarking.reproducible_fixtures
    - jido_memory.matrix.benchmarking.results_inform_but_do_not_redefine_core
- kind: source_file
  target: .spec/planning/provider_benchmarking/README.md
  covers:
    - jido_memory.matrix.benchmarking.shared_overlap_first
    - jido_memory.matrix.benchmarking.provider_specific_lane
    - jido_memory.matrix.benchmarking.reproducible_fixtures
    - jido_memory.matrix.benchmarking.results_inform_but_do_not_redefine_core
```
