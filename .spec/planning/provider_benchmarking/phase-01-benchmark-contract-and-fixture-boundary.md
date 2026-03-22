# Phase 1 - Benchmark Contract and Fixture Boundary

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Runtime`
- `Jido.Memory.Plugin`
- `Jido.Memory.Provider`
- `Jido.Memory.ProviderContract`
- `Jido.Memory.ProviderFixtures`

## Relevant Assumptions / Defaults
- Benchmark work starts with repository-owned fixtures and dry local runs.
- The shared benchmark path compares only overlapping canonical memory flows.
- No benchmark implementation lands in this phase beyond fixture and contract scaffolding.

[ ] 1 Phase 1 - Benchmark Contract and Fixture Boundary
  Define the benchmark contract, fixture ownership model, and shared provider matrix so later harness work has a stable scope.

  [ ] 1.1 Section - Shared Benchmark Scope
    Describe the canonical provider flows and provider matrix that the shared benchmark path will cover.

    [ ] 1.1.1 Task - Define the shared benchmark provider matrix
      Lock the benchmark paths that every common benchmark run should consider.

      [ ] 1.1.1.1 Subtask - Define the shared matrix as built-in `:basic`, built-in `:tiered`, built-in `:mirix`, and the external-provider reference path.
      [ ] 1.1.1.2 Subtask - Limit the shared matrix to overlapping canonical operations such as remember, retrieve, recall, provider selection, and explainability where supported.
      [ ] 1.1.1.3 Subtask - Keep provider-direct ingestion, vault workflows, and durable-backend-only comparisons out of the shared matrix.

  [ ] 1.2 Section - Fixture Ownership and Local Reproducibility
    Define how benchmark fixtures are stored and how local runs stay reproducible without service-heavy setup.

    [ ] 1.2.1 Task - Define repository-owned fixture rules
      Make benchmark data easy to version, review, and run locally.

      [ ] 1.2.1.1 Subtask - Keep benchmark fixtures in repository-owned paths under `test/support` or a dedicated benchmark fixture directory.
      [ ] 1.2.1.2 Subtask - Prefer deterministic textual and structured record fixtures over service-backed corpora in the first harness cut.
      [ ] 1.2.1.3 Subtask - Make durable-backend or provider-direct fixture packs opt-in rather than required for local baseline runs.

  [ ] 1.3 Section - Benchmark Contract Helpers
    Define the helper surfaces that later benchmark phases will reuse for matrix execution and result comparison.

    [ ] 1.3.1 Task - Plan benchmark contract helper modules
      Outline the helper seams for scenario execution, metric capture, and output formatting without implementing them yet.

      [ ] 1.3.1.1 Subtask - Define a shared benchmark scenario contract for setup, execution, and result assertions.
      [ ] 1.3.1.2 Subtask - Define a metric envelope for latency, result parity, explainability richness, and provider-specific notes.
      [ ] 1.3.1.3 Subtask - Keep result storage and reporting file formats explicit before harness code is introduced.

  [ ] 1.4 Section - Phase 1 Integration Tests
    Define the dry-run or fixture-validation checks that will confirm the benchmark contract and fixture boundary once implemented.

    [ ] 1.4.1 Task - Shared matrix dry-run scenarios
      Describe how the first phase will prove the benchmark scope is coherent before performance-oriented harness code exists.

      [ ] 1.4.1.1 Subtask - Add a dry-run validation that enumerates the shared provider matrix and benchmark scenario definitions.
      [ ] 1.4.1.2 Subtask - Add fixture validation that checks repository-owned benchmark fixtures load deterministically.
      [ ] 1.4.1.3 Subtask - Verify the phase stays implementation-light and does not add real benchmark execution yet.
