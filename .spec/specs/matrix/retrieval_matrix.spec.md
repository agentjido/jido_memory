# Retrieval Matrix

This subject defines how canonical retrieval coexists with richer provider-side
planning and explanation behavior.

## Intent

Keep retrieve/3 stable while allowing more specialized providers to expose
routing traces, retrieval plans, and query extensions safely.

```spec-meta
id: jido_memory.matrix.retrieval
kind: architecture
status: draft
summary: Draft matrix for canonical retrieval, explainability traces, and provider-native query extensions.
surface:
  - .spec/decisions/0001-additive-provider-extension-boundary.md
  - lib/jido_memory.ex
  - lib/jido_memory/query.ex
  - lib/jido_memory/capability/explainable_retrieval.ex
decisions:
  - jido_memory.provider_extension_boundary
```

## Requirements

```spec-requirements
- id: jido_memory.matrix.retrieval.canonical_result_shape
  statement: The canonical retrieve/3 contract shall continue returning the shared record-oriented result shape even when a provider internally performs active planning or routed retrieval.
  priority: must
  stability: evolving
- id: jido_memory.matrix.retrieval.explanation_trace_lane
  statement: Retrieval plans, routing traces, and other provider-native diagnostic details shall be exposed through explainability metadata or provider-direct APIs rather than a new canonical retrieve/3 result format.
  priority: must
  stability: evolving
- id: jido_memory.matrix.retrieval.query_extension_hints
  statement: Provider-specific retrieval controls shall be carried through optional hints or extensions rather than mandatory additions to the base Jido.Memory.Query contract.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: jido_memory.matrix.retrieval.tiered_explainability_path
  given:
    - a provider that adds tier-aware explanation details to canonical retrieval
  when:
    - a caller asks for retrieval explanation
  then:
    - the explanation contains provider-native context while retrieve/3 continues returning the shared record-oriented result shape
  covers:
    - jido_memory.matrix.retrieval.canonical_result_shape
    - jido_memory.matrix.retrieval.explanation_trace_lane
- id: jido_memory.matrix.retrieval.active_planning_path
  given:
    - a provider such as Mirix that generates an internal retrieval plan before selecting memory sources
  when:
    - the provider is used through the canonical runtime surface
  then:
    - any plan-specific controls remain optional hints or provider-direct features rather than becoming mandatory base query fields
  covers:
    - jido_memory.matrix.retrieval.explanation_trace_lane
    - jido_memory.matrix.retrieval.query_extension_hints
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/0001-additive-provider-extension-boundary.md
  covers:
    - jido_memory.matrix.retrieval.canonical_result_shape
    - jido_memory.matrix.retrieval.explanation_trace_lane
    - jido_memory.matrix.retrieval.query_extension_hints
```
