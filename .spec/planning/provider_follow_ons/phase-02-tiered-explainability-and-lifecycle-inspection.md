# Phase 2 - Tiered Explainability and Lifecycle Inspection

Description: deepen the built-in Tiered provider so users can inspect why memories were retrieved, promoted, or consolidated instead of treating tier movement as a black box.

## Section 2.1 - Retrieval Explainability for Tiered
Description: add a first-class explanation surface for cross-tier retrieval behavior.

### Task 2.1.1 - Implement `explain_retrieval/3` for Tiered
Description: make Tiered satisfy the retrieval explainability capability with provider-native details.
- [x] Return tier participation, match reasons, and ranking or filtering context for retrieval results.
- [x] Distinguish records found in short, mid, and long-term layers in the explanation payload.
- [x] Keep the explanation shape compatible with the common runtime capability gate.

### Task 2.1.2 - Define stable explanation payloads
Description: make explainability useful to applications without overcommitting to provider internals.
- [x] Decide which explanation fields are canonical and which are Tiered-specific extensions.
- [x] Add provider metadata describing explanation availability and payload scope.
- [x] Keep unsupported explainability behavior explicit for providers that do not implement it.

## Section 2.2 - Promotion and Consolidation Introspection
Description: expose lifecycle reasoning so promotion across tiers can be understood and debugged.

### Task 2.2.1 - Add promotion rationale metadata
Description: make Tiered record why a memory was eligible or ineligible for promotion.
- [x] Record promotion scores, threshold comparisons, and source tier information in provider-managed metadata.
- [x] Distinguish transient retrieval metadata from durable lifecycle metadata.
- [x] Keep metadata bounded so repeated consolidations do not produce unbounded record growth.

### Task 2.2.2 - Add lifecycle inspection helpers
Description: make it easy to query promotion and consolidation outcomes through supported APIs.
- [x] Add provider or runtime helpers for summarizing recent consolidation outcomes.
- [x] Expose promotion counts, skipped reasons, and destination tiers in a stable inspection shape.
- [x] Decide whether lifecycle inspection belongs in `info/3`, a new capability helper, or provider-direct operations.

## Section 2.3 - Tiered Explainability Docs and Examples
Description: document how explainability and lifecycle inspection should be used in practice.

### Task 2.3.1 - Add docs-backed explainability examples
Description: show retrieval explanation and promotion inspection in the same built-in Tiered story users already understand.
- [x] Add README or guide examples for `Runtime.explain_retrieval/3` with Tiered.
- [x] Show how lifecycle inspection explains promotion from short to mid and mid to long.
- [x] Explain the tradeoff between lightweight metadata and richer audit detail.

### Task 2.3.2 - Clarify non-goals for Tiered explainability
Description: prevent this phase from expanding into full observability or journaling.
- [x] Document that Tiered explainability is not a replacement for MemoryOS journaling and replay.
- [x] Keep request-level auditing and replay explicitly outside this phase.
- [x] Capture any open questions around ranking semantics and explanation depth before expanding further.

## Section 2.4 - Phase 2 Integration Tests
Description: validate explainability and lifecycle inspection end to end through the built-in Tiered provider.

### Task 2.4.1 - Retrieval explanation scenarios
Description: prove Tiered explanation data is returned consistently through the runtime facade.
- [ ] Verify `Runtime.explain_retrieval/3` returns tier-aware explanation data for Tiered.
- [ ] Verify explanation payloads line up with actual retrieval results and selected tiers.
- [ ] Verify Basic and other non-explainable providers continue to return unsupported-capability results.

### Task 2.4.2 - Lifecycle inspection scenarios
Description: prove promotion reasoning is inspectable and consistent with consolidation behavior.
- [ ] Verify consolidation results include promotion rationale for promoted and skipped records.
- [ ] Verify lifecycle inspection helpers reflect actual tier transitions and counts.
- [ ] Verify the docs-backed explainability examples execute against tested Tiered configurations.
