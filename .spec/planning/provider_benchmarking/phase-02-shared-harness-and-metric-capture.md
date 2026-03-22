# Phase 2 - Shared Harness and Metric Capture

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Runtime`
- `Jido.Memory.Plugin`
- `Jido.Memory.ProviderRegistry`
- `Jido.Memory.ProviderFixtures`
- Planned benchmark helper modules

## Relevant Assumptions / Defaults
- This phase implements only the shared cross-provider benchmark path.
- Metric capture stays focused on overlapping canonical behavior.
- Default runs remain local and service-light.

[ ] 2 Phase 2 - Shared Harness and Metric Capture
  Implement the shared benchmark harness, metric envelope, and baseline result capture for comparable canonical flows across the provider matrix.

  [ ] 2.1 Section - Shared Scenario Execution Harness
    Build the common runner that can execute the same benchmark scenario across the shared provider matrix.

    [ ] 2.1.1 Task - Implement provider-matrix scenario execution
      Make the harness run the same canonical scenario against each shared provider path.

      [ ] 2.1.1.1 Subtask - Execute remember, retrieve, recall, and provider-selection scenarios across the shared provider matrix.
      [ ] 2.1.1.2 Subtask - Normalize scenario inputs so providers are compared on overlapping behavior only.
      [ ] 2.1.1.3 Subtask - Keep provider-specific failures or unsupported capabilities visible but non-fatal where the scenario is outside the shared overlap.

  [ ] 2.2 Section - Metric Capture and Result Envelopes
    Capture benchmark output in a stable structure that can be compared and reported later.

    [ ] 2.2.1 Task - Implement the benchmark metric envelope
      Record the metrics and notes needed for cross-provider comparison without overfitting to one provider.

      [ ] 2.2.1.1 Subtask - Capture latency and scenario pass/fail signals for each provider-path execution.
      [ ] 2.2.1.2 Subtask - Capture result parity and explainability availability for overlapping retrieval scenarios.
      [ ] 2.2.1.3 Subtask - Record provider-specific notes separately from the shared metric fields.

  [ ] 2.3 Section - Local Baseline Execution and Storage
    Store and validate local benchmark outputs in a deterministic way.

    [ ] 2.3.1 Task - Add baseline result output paths
      Make local benchmark results inspectable and diff-friendly.

      [ ] 2.3.1.1 Subtask - Write shared benchmark results to a deterministic repository-local output path.
      [ ] 2.3.1.2 Subtask - Keep generated benchmark outputs outside `.spec/specs/` and out of current-truth documents.
      [ ] 2.3.1.3 Subtask - Document the expected result format for later reporting phases.

  [ ] 2.4 Section - Phase 2 Integration Tests
    Verify the shared harness can run the benchmark matrix and produce stable outputs.

    [ ] 2.4.1 Task - Shared harness benchmark scenarios
      Confirm that the harness executes the shared provider matrix consistently.

      [ ] 2.4.1.1 Subtask - Verify the same benchmark scenario runs across `:basic`, `:tiered`, `:mirix`, and the external-provider reference path.
      [ ] 2.4.1.2 Subtask - Verify metric envelopes are complete and deterministic across repeated local runs.
      [ ] 2.4.1.3 Subtask - Verify shared benchmark output paths are generated without widening the canonical runtime or plugin surface.
