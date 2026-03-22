# Phase 3 - MIRIX Built-In Provider Memory-Type Substrate

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `Jido.Memory.Provider.Mirix`
- `Jido.Memory.ProviderRegistry`
- `Jido.Memory.Provider.Basic`
- `Jido.Memory.Store`
- `Jido.Memory.Record`
- `Jido.Memory.ProviderContract`

## Relevant Assumptions / Defaults
- MIRIX is added as a built-in provider alias `:mirix`.
- MIRIX uses module-level manager components in v1 and does not require supervised child specs.
- Each MIRIX memory type has its own configurable store pair with ETS defaults.

[x] 3 Phase 3 - MIRIX Built-In Provider Memory-Type Substrate
  Implement the built-in MIRIX provider, its six memory-type substrates, and the canonical provider flow mapping needed for shared core operations.

  [x] 3.1 Section - MIRIX Provider Module and Configuration Baseline
    Create the built-in MIRIX provider module and define its stable config and metadata model.

    [x] 3.1.1 Task - Add `Jido.Memory.Provider.Mirix` as a built-in provider
      Introduce MIRIX as a first-class built-in provider choice that satisfies the canonical provider contract.

      [x] 3.1.1.1 Subtask - Implement `validate_config/1`, `child_specs/1`, `init/1`, `capabilities/1`, `remember/3`, `get/3`, `retrieve/3`, `forget/3`, `prune/2`, and `info/2` on `Jido.Memory.Provider.Mirix`.
      [x] 3.1.1.2 Subtask - Report MIRIX capabilities as `core: true`, `retrieval.explainable: true`, `retrieval.active: true`, `retrieval.memory_types: true`, `ingestion.batch: true`, `ingestion.multimodal: true`, `ingestion.routed: true`, `governance.protected_memory: true`, `governance.exact_preservation: true`, and `governance.access: :provider_direct`.
      [x] 3.1.1.3 Subtask - Return empty `child_specs/1` in v1 and describe MIRIX manager modules through `info/2` and provider metadata rather than mandatory supervised runtime children.

  [x] 3.2 Section - MIRIX Memory-Type Manager Modules and Record Mapping
    Implement the internal MIRIX manager modules and map all MIRIX memory types back to the canonical record model.
    Completed by adding the built-in `Core`, `Episodic`, `Semantic`, `Procedural`, `Resource`, `Vault`, and `MetaRouter` modules and by preserving the exact MIRIX memory type in `record.metadata["mirix"]["memory_type"]` while keeping canonical `Record.class` values stable.

  [x] 3.3 Section - MIRIX Core Provider Flow Mapping
    Implement the canonical provider callbacks over the MIRIX manager graph and store topology.
    Completed by routing canonical writes and reads through the MIRIX store topology, supporting built-in alias resolution for `:mirix`, and keeping vault records out of canonical `remember/3` and `retrieve/3`.

  [x] 3.4 Section - Phase 3 Integration Tests
    Validate MIRIX as a built-in provider that satisfies the canonical core contract and built-in provider selection model.
    Completed with provider, plugin, and dedicated MIRIX integration coverage for core flow, alias equivalence, manager metadata, record mapping, namespace isolation, and vault exclusion from canonical retrieval.
