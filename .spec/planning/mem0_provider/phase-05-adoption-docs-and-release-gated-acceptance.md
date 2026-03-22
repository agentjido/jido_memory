# Phase 5 - Adoption, Docs, and Release-Gated Acceptance

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Runtime`
- `Jido.Memory.Plugin`
- `Jido.Memory.Provider.Mem0`
- `Jido.Memory.ProviderRegistry`
- `.spec/specs/provider_mem0.spec.md`
- `.spec/planning/provider_benchmarking/*.md`

## Relevant Assumptions / Defaults
- Phase 5 is where the Mem0 provider becomes a documented and supportable path in `jido_memory`.
- Benchmarking hooks align with the separate provider benchmarking plan rather than implementing benchmark infrastructure here.
- The shared plugin remains core-only even after Mem0 adoption.

[ ] 5 Phase 5 - Adoption, Docs, and Release-Gated Acceptance
  Complete the Mem0 provider rollout with examples, spec alignment, benchmark hooks, and final cross-provider acceptance coverage.

  [ ] 5.1 Section - Plugin, Runtime, and Example Adoption
    Show how the Mem0 provider is used through the existing common memory surface and its provider-direct advanced operations.

    [ ] 5.1.1 Task - Add Mem0 adoption examples and fixtures
      Make the Mem0 provider practical to evaluate and adopt.

      [ ] 5.1.1.1 Subtask - Add examples showing `Jido.Memory.Plugin` with `provider: :mem0` for canonical remember and retrieve flows.
      [ ] 5.1.1.2 Subtask - Add examples showing provider-direct Mem0 ingestion, feedback, history, or export workflows.
      [ ] 5.1.1.3 Subtask - Add acceptance fixtures that switch the same agent between `:basic`, `:tiered`, `:mirix`, `:mem0`, and the external-provider reference path without changing common plugin code.

  [ ] 5.2 Section - Spec, Topology, and Benchmark-Hook Alignment
    Bring the implementation and support docs into line once the Mem0 provider is real.

    [ ] 5.2.1 Task - Update current-truth and support documents for Mem0
      Keep the Spec Led workspace and user-facing docs aligned with the implemented provider boundary.

      [ ] 5.2.1.1 Subtask - Update provider architecture, capability, facade, and matrix subjects to reflect implemented Mem0 behavior.
      [ ] 5.2.1.2 Subtask - Update `.spec/topology.md` to add Mem0 to the provider topology if it becomes part of the implemented built-in matrix.
      [ ] 5.2.1.3 Subtask - Add benchmark fixture and scenario hooks that align with the separate provider benchmarking plan without implementing benchmark infrastructure inside this phase.

  [ ] 5.3 Section - Release Matrix and Acceptance Hardening
    Decide how Mem0 enters the support matrix and lock the final compatibility expectations.

    [ ] 5.3.1 Task - Extend the release-gated provider acceptance matrix
      Treat Mem0 as a release-aware provider path only once acceptance coverage is stable.

      [ ] 5.3.1.1 Subtask - Add Mem0 to the release-gated acceptance matrix alongside the existing provider paths when it proves stable enough.
      [ ] 5.3.1.2 Subtask - Keep `:basic` as the default provider and verify existing callers remain unchanged.
      [ ] 5.3.1.3 Subtask - Keep benchmark work and release gating decoupled enough that unstable performance instrumentation does not block normal development.

  [ ] 5.4 Section - Phase 5 Integration Tests
    Validate the completed Mem0 provider path end to end from the consumer point of view.

    [ ] 5.4.1 Task - Cross-provider runtime and plugin scenarios
      Verify the shared memory surface stays stable when Mem0 joins the supported provider matrix.

      [ ] 5.4.1.1 Subtask - Verify the same canonical memory workflow succeeds through `Jido.Memory.Plugin` when backed by `:basic`, `:tiered`, `:mirix`, `:mem0`, and the external-provider reference path.
      [ ] 5.4.1.2 Subtask - Verify `Runtime.explain_retrieval/3` remains selective and provider-shaped across the supported matrix.
      [ ] 5.4.1.3 Subtask - Verify Mem0 scoped retrieval and provider-direct advanced operations do not distort existing caller behavior.

    [ ] 5.4.2 Task - Mem0 adoption and release scenarios
      Verify the Mem0 provider is documented, supportable, and consistent with the broader provider roadmap.

      [ ] 5.4.2.1 Subtask - Verify Mem0 provider-direct advanced operations remain clearly absent from the shared plugin/action surface.
      [ ] 5.4.2.2 Subtask - Verify the final docs, topology, and Mem0 specs match the implemented provider boundary.
      [ ] 5.4.2.3 Subtask - Verify Mem0 benchmark hooks align with the separate benchmarking plan without silently introducing a second benchmark process.
