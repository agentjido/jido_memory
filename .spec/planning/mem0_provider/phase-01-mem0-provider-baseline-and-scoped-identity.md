# Phase 1 - Mem0 Provider Baseline and Scoped Identity

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Provider`
- `Jido.Memory.ProviderRef`
- `Jido.Memory.ProviderRegistry`
- `Jido.Memory.Runtime`
- `Jido.Memory.Plugin`
- `Jido.Memory.Record`

## Relevant Assumptions / Defaults
- The Mem0-style provider is introduced as `Jido.Memory.Provider.Mem0`.
- The built-in provider alias for this path is `:mem0`.
- Scoped identities remain provider-level configuration and metadata, not a new provider-selection dimension.
- Phase 1 establishes the provider substrate and scoped-identity model before extraction, reconciliation, or graph augmentation land.

[ ] 1 Phase 1 - Mem0 Provider Baseline and Scoped Identity
  Implement the built-in Mem0-style provider module, reserve its built-in alias, and establish how scoped long-term memory identities fit behind the canonical provider contract.

  [x] 1.1 Section - Built-In Provider Module and Catalog Baseline
    Introduce the Mem0 provider module and make it available as a first-class built-in provider choice without changing the default provider path.
    Completed by adding the built-in `Jido.Memory.Provider.Mem0` baseline module, reserving the built-in `:mem0` alias, and exposing the initial Mem0 capability and topology metadata.

    [x] 1.1.1 Task - Add the built-in Mem0 provider module
      Create the provider module and lock its core contract surface before advanced Mem0-specific behaviors are added.

      [x] 1.1.1.1 Subtask - Add `Jido.Memory.Provider.Mem0` implementing `validate_config/1`, `child_specs/1`, `init/1`, `capabilities/1`, `remember/3`, `get/3`, `retrieve/3`, `forget/3`, `prune/2`, and `info/2`.
      [x] 1.1.1.2 Subtask - Add `:mem0` to `Jido.Memory.ProviderRegistry.built_in_aliases/0` and keep explicit module selection equivalent to alias-based selection.
      [x] 1.1.1.3 Subtask - Keep `:basic` as the default provider when no provider is selected.

    [x] 1.1.2 Task - Define the baseline Mem0 capability map
      Reserve the structured capability vocabulary that later phases will extend.

      [x] 1.1.2.1 Subtask - Report core support for canonical memory operations.
      [x] 1.1.2.2 Subtask - Reserve retrieval capability keys for explainability, scoped retrieval, and optional graph augmentation.
      [x] 1.1.2.3 Subtask - Reserve provider-direct advanced-operation metadata for feedback, export, history, and maintenance controls.

  [ ] 1.2 Section - Scoped Identity Model and Configuration Baseline
    Define how user, agent, app, and run scoping are expressed through provider configuration and metadata without changing provider resolution precedence.

    [ ] 1.2.1 Task - Define the scoped identity config model
      Make Mem0-style scoping explicit and reusable through the provider's own configuration surface.

      [ ] 1.2.1.1 Subtask - Support provider config blocks for default user, agent, app, and run scope handling.
      [ ] 1.2.1.2 Subtask - Define how scope ids are derived from target data, runtime opts, and provider config with deterministic precedence.
      [ ] 1.2.1.3 Subtask - Keep canonical namespace support intact while allowing Mem0 scopes to live in provider metadata.

    [ ] 1.2.2 Task - Map scoped identities into canonical records and info payloads
      Preserve the shared record model while surfacing provider-native scoping context clearly.

      [ ] 1.2.2.1 Subtask - Store effective scope ids in provider metadata and record metadata rather than inventing a second public record type.
      [ ] 1.2.2.2 Subtask - Expose scope configuration and effective scope policy through `info/2`.
      [ ] 1.2.2.3 Subtask - Keep provider selection precedence independent from scope resolution precedence.

  [ ] 1.3 Section - Canonical Core Flow Mapping
    Route the shared remember, get, retrieve, forget, and prune flows through the Mem0 provider without introducing extraction or graph-specific behavior yet.

    [ ] 1.3.1 Task - Implement the baseline canonical flow path
      Make the Mem0 provider behave like a normal provider for core runtime and plugin use before advanced memory maintenance lands.

      [ ] 1.3.1.1 Subtask - Support canonical `remember/3` for direct structured record writes into the Mem0 backing store.
      [ ] 1.3.1.2 Subtask - Support canonical `get/3`, `retrieve/3`, `forget/3`, and `prune/2` within the configured scope model.
      [ ] 1.3.1.3 Subtask - Keep `child_specs/1` empty in the first cut unless background maintenance processes become mandatory later.

  [ ] 1.4 Section - Phase 1 Integration Tests
    Validate the built-in provider baseline, the scoped-identity model, and canonical runtime compatibility before extraction-and-reconciliation behavior is added.

    [ ] 1.4.1 Task - Built-in provider baseline scenarios
      Verify the Mem0 provider satisfies the canonical provider contract and built-in alias path.

      [ ] 1.4.1.1 Subtask - Verify `provider: :mem0` and `provider: Jido.Memory.Provider.Mem0` are equivalent.
      [ ] 1.4.1.2 Subtask - Verify `ProviderContract.exercise_core_flow/5` passes for Mem0 through the baseline scoped path.
      [ ] 1.4.1.3 Subtask - Verify `info/2` exposes provider and scope metadata without changing the shared runtime result shape.

    [ ] 1.4.2 Task - Scoped identity scenarios
      Verify Mem0-style scope handling stays deterministic and additive.

      [ ] 1.4.2.1 Subtask - Verify user, agent, app, and run scope ids resolve predictably from target data and opts.
      [ ] 1.4.2.2 Subtask - Verify canonical namespace support still works alongside provider-native scope ids.
      [ ] 1.4.2.3 Subtask - Verify existing built-in providers remain unaffected by the new Mem0 provider baseline.
