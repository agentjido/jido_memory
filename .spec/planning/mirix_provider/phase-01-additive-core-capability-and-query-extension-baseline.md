# Phase 1 - Additive Core Capability and Query Extension Baseline

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Provider`
- `Jido.Memory.Capabilities`
- `Jido.Memory.Capability.Ingestion`
- `Jido.Memory.Query`
- `Jido.Memory.ProviderRegistry`
- `Jido.Memory.ProviderRef`

## Relevant Assumptions / Defaults
- The required provider callbacks do not change in this phase.
- Query extensions become the canonical lane for provider-specific retrieval controls.
- `:mirix` is reserved as a built-in provider alias even before the provider implementation lands.

[x] 1 Phase 1 - Additive Core Capability and Query Extension Baseline
  Implement the core additive seams required by the ADR and matrix specs so specialized providers can extend `jido_memory` without inflating the required provider contract.

  [x] 1.1 Section - Optional Ingestion Capability and Capability Map Expansion
    Define the new optional ingestion capability family and expand capability metadata so MIRIX-style providers can advertise richer write flows without changing `remember/3`.

    [x] 1.1.1 Task - Add the canonical ingestion capability family
      Create a provider capability boundary for batch, multimodal, and routed ingestion while keeping the shared runtime and plugin unchanged in v1.

      [x] 1.1.1.1 Subtask - Add `Jido.Memory.Capability.Ingestion` with `ingest(target, payload, opts)` returning `{:ok, map()} | {:error, term()}` and treating `payload` as a provider-owned map.
      [x] 1.1.1.2 Subtask - Expand `Jido.Memory.Capabilities.default/0` and normalization to include `ingestion: %{batch: false, multimodal: false, routed: false, access: :none}`.
      [x] 1.1.1.3 Subtask - Keep `Basic` and `Tiered` capability maps explicit and negative for ingestion support so unsupported-capability behavior remains deterministic.

    [x] 1.1.2 Task - Reserve MIRIX capability vocabulary
      Define the capability keys MIRIX will report so later phases do not have to renegotiate metadata shape.

      [x] 1.1.2.1 Subtask - Reserve retrieval capability keys for `active`, `memory_types`, and `provider_extensions`.
      [x] 1.1.2.2 Subtask - Reserve governance capability keys for `protected_memory`, `exact_preservation`, and `access`.
      [x] 1.1.2.3 Subtask - Reserve ingestion capability keys for `batch`, `multimodal`, `routed`, and `access`.

  [x] 1.2 Section - Query Extension Baseline and Compatibility Normalization
    Extend the canonical query model so provider-native retrieval controls have one stable lane without turning provider-specific options into required base fields.

    [x] 1.2.1 Task - Add canonical query extension support
      Make provider-specific retrieval hints travel through the shared query contract in one backward-compatible field.

      [x] 1.2.1.1 Subtask - Add optional `extensions` map to `Jido.Memory.Query` with normalized default `%{}`.
      [x] 1.2.1.2 Subtask - Preserve existing query filters and result semantics unchanged when `extensions` is empty.
      [x] 1.2.1.3 Subtask - Ensure `Runtime.retrieve/3` and `Runtime.explain_retrieval/3` preserve `Query.extensions` all the way to provider callbacks.

    [x] 1.2.2 Task - Normalize existing Tiered-specific query controls into extensions
      Keep current Tiered callers working while establishing the new canonical extension lane.

      [x] 1.2.2.1 Subtask - Normalize `tier`, `tiers`, and `tier_mode` query attrs into `extensions.tiered` internally while preserving current direct attrs as accepted inputs.
      [x] 1.2.2.2 Subtask - Add `query_extensions` as the canonical caller-facing action/runtime attr for provider-native retrieval controls.
      [x] 1.2.2.3 Subtask - Keep Tiered explanation payloads and retrieval behavior stable under both legacy attrs and the normalized extension path.

  [x] 1.3 Section - Built-In Provider Catalog Baseline
    Reserve MIRIX as a first-class built-in provider choice before implementing its provider module.

    [x] 1.3.1 Task - Extend the built-in provider registry for MIRIX
      Make the provider catalog and alias resolution model explicit for the upcoming built-in provider.

      [x] 1.3.1.1 Subtask - Add `:mirix` to `Jido.Memory.ProviderRegistry.built_in_aliases/0` and document it as a reserved built-in alias.
      [x] 1.3.1.2 Subtask - Keep alias precedence and explicit module resolution unchanged in `ProviderRef`.
      [x] 1.3.1.3 Subtask - Preserve invalid-alias and invalid-provider error shapes for existing callers.

  [x] 1.4 Section - Phase 1 Integration Tests
    Validate the new capability and query seams without requiring MIRIX itself to exist yet.

    [x] 1.4.1 Task - Capability and query-extension scenarios
      Verify the additive core baseline is in place and backward-compatible.

      [x] 1.4.1.1 Subtask - Verify `Basic` and `Tiered` expose deterministic negative ingestion capability metadata.
      [x] 1.4.1.2 Subtask - Verify `Query.extensions` survives `Runtime.retrieve/3` and `Runtime.explain_retrieval/3` dispatch unchanged.
      [x] 1.4.1.3 Subtask - Verify legacy Tiered query attrs and normalized `extensions.tiered` produce identical retrieval and explanation behavior.

    [x] 1.4.2 Task - Built-in catalog baseline scenarios
      Verify MIRIX enters the catalog cleanly before implementation.

      [x] 1.4.2.1 Subtask - Verify `ProviderRegistry.resolve_alias(:mirix)` resolves once the alias is reserved.
      [x] 1.4.2.2 Subtask - Verify `ProviderRef` still rejects unresolved modules or invalid alias maps deterministically.
      [x] 1.4.2.3 Subtask - Verify the release-gated provider catalog still reports `:basic` and `:tiered` unchanged.
