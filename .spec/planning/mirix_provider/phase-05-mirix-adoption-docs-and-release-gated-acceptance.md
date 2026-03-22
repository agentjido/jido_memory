# Phase 5 - MIRIX Adoption, Docs, and Release-Gated Acceptance

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Runtime`
- `Jido.Memory.Plugin`
- `Jido.Memory.Provider.Mirix`
- `Jido.Memory.ProviderRegistry`
- `.spec/specs/provider_*`
- `.spec/specs/matrix/*.spec.md`

## Relevant Assumptions / Defaults
- Phase 5 finishes the built-in MIRIX story as a supported built-in provider choice.
- The release-gated matrix after this phase is `:basic`, `:tiered`, `:mirix`, and the external-provider reference path.
- The shared plugin remains core-only even after MIRIX adoption.

[x] 5 Phase 5 - MIRIX Adoption, Docs, and Release-Gated Acceptance
  Complete the built-in MIRIX rollout with stable docs, examples, acceptance coverage, and spec alignment.

  [x] 5.1 Section - Plugin, Runtime, and Example Adoption
    Show MIRIX as a built-in provider choice through the existing common surfaces without widening the plugin boundary.
    Completed by adding a docs-backed MIRIX example module, README adoption examples, and built-in provider guide coverage for common `:mirix` plugin usage plus provider-direct ingest and vault workflows.

  [x] 5.2 Section - Spec, ADR, and Topology Alignment
    Bring the implementation and the Spec Led workspace into full alignment.
    Completed by updating the provider architecture, capability, facade, matrix, and topology documents so the current-truth workspace reflects the shipped built-in MIRIX provider.

  [x] 5.3 Section - Release Matrix and Acceptance Hardening
    Treat MIRIX as a release-gated built-in provider and finish the final compatibility checks.
    Completed by adding MIRIX to the published acceptance matrix and extending `mix test.acceptance` so the release gate exercises the MIRIX Phase 3 and Phase 4 acceptance paths.

  [x] 5.4 Section - Phase 5 Integration Tests
    Validate the completed architecture end to end from the consumer point of view.
    Completed with final cross-provider acceptance coverage for Basic, Tiered, Mirix, and the external-provider reference path, docs-backed example execution, explainability differentiation, and provider-direct boundary assertions.
