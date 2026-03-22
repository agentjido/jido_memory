---
id: jido_memory.provider_extension_boundary
status: accepted
date: 2026-03-21
affects:
  - jido_memory.provider_core
  - jido_memory.provider_capabilities
  - jido_memory.provider_facade
  - jido_memory.matrix.provider_surface
  - jido_memory.matrix.ingestion
  - jido_memory.matrix.retrieval
  - jido_memory.matrix.governance
---

# ADR 0001: Additive Provider Extension Boundary

## Context

`jido_memory` now owns the canonical provider contract and the standard built-in
provider catalog. As the provider model broadens, we need to support richer
providers that may introduce multimodal ingestion, memory-type routing, active
retrieval planning, protected exact-preservation stores, and provider-owned
runtime processes.

Those richer providers should be able to plug into the canonical memory layer
without forcing `Basic`, `Tiered`, or future minimal providers to implement the
same specialized behaviors.

## Decision

<!-- covers: jido_memory.provider_core.required_contract_stability -->
<!-- covers: jido_memory.provider_core.bootstrap_boundary -->
<!-- covers: jido_memory.provider_core.provider_bundle_selection -->
<!-- covers: jido_memory.provider_capabilities.additive_extension_boundary -->
<!-- covers: jido_memory.provider_capabilities.ingestion_capability_family -->
<!-- covers: jido_memory.provider_capabilities.explainability_routing_trace_boundary -->
<!-- covers: jido_memory.provider_capabilities.governance_protected_memory -->
<!-- covers: jido_memory.provider_capabilities.typed_unsupported_error -->
<!-- covers: jido_memory.provider_facade.narrow_runtime_boundary -->
<!-- covers: jido_memory.provider_facade.provider_native_extension_boundary -->
<!-- covers: jido_memory.provider_facade.shared_record_query_contract -->
<!-- covers: jido_memory.matrix.provider_surface.classified_extension_lanes -->
<!-- covers: jido_memory.matrix.provider_surface.core_lane_stability -->
<!-- covers: jido_memory.matrix.provider_surface.provider_direct_escape_hatch -->
<!-- covers: jido_memory.matrix.ingestion.optional_ingestion_lane -->
<!-- covers: jido_memory.matrix.ingestion.core_write_stability -->
<!-- covers: jido_memory.matrix.ingestion.plugin_core_only_boundary -->
<!-- covers: jido_memory.matrix.retrieval.canonical_result_shape -->
<!-- covers: jido_memory.matrix.retrieval.explanation_trace_lane -->
<!-- covers: jido_memory.matrix.retrieval.query_extension_hints -->
<!-- covers: jido_memory.matrix.governance.protected_memory_lane -->
<!-- covers: jido_memory.matrix.governance.no_mandatory_vault_core -->
<!-- covers: jido_memory.matrix.governance.selective_runtime_exposure -->

We will extend the provider system additively.

1. The required provider core stays small.
   - The mandatory provider callbacks remain focused on validation,
     bootstrapping, capability reporting, and the shared remember/get/retrieve/
     forget/prune/info operations.
   - Specialized concerns such as multimodal ingestion, memory-type routing,
     retrieval plans, and protected vault semantics do not become mandatory
     callbacks for every provider.

2. New advanced behavior lands through optional capability families.
   - Reusable advanced features should be represented as optional capabilities.
   - A distinct ingestion-oriented capability family is the preferred way to
     model batch, multimodal, or routed write flows.

3. The common runtime facade remains selective.
   - `Jido.Memory.Runtime` standardizes only broadly reusable operations.
   - Provider-specific manager controls, retrieval plans, and specialized
     workflows stay in capability-specific helpers, `info/3`, or provider-direct
     APIs.

4. Canonical retrieval stays stable while explainability gets richer.
   - `retrieve/3` continues to return the canonical flat record-oriented result.
   - Retrieval plans, routing traces, and similar provider-native explanations
     are exposed through explainability metadata rather than a new shared result
     shape.

5. Protected or exact-preservation memory stays out of the required core.
   - Vault-style semantics belong in governance capabilities or provider-direct
     APIs.
   - Providers that do not support protected memory are not required to emulate
     it.

6. Provider-specific query or ingestion features stay in extensions.
   - The base `Jido.Memory.Query` contract remains canonical.
   - Provider-native retrieval or ingestion controls flow through hints,
     extensions, explainability payloads, or provider-direct APIs instead of
     mandatory base fields.

## Consequences

### Positive

- `Basic` stays small and easy to implement.
- `Tiered` can continue evolving without becoming the shape of every provider.
- More specialized providers can plug in without distorting the canonical core.
- The plugin and runtime facade remain stable for agent-facing usage.

### Tradeoffs

- Some advanced features will not have first-class runtime wrappers at first.
- Tooling must inspect capability maps and provider metadata to discover richer
  behavior.
- Documentation and matrix specs need to stay clear about which features are
  canonical, optional, or provider-direct.

### Follow-on Work

- Add matrix specs that classify provider features into core, optional, and
  provider-direct lanes.
- Add capability definitions and implementation plans for any new optional
  families such as ingestion.
- Keep acceptance coverage aligned with the release-gated provider matrix.
