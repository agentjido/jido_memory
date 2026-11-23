# 02_03 Resolve an edit that arrives out of order

The model proposes a resolution against revision 1. A support operator
corrects the active record to revision 2 before reviewing the proposal.
Approval checks the proposal's expected revision and rejects the stale
write. Redelivery of the proposal's Signal returns a duplicate decision
without a model call.

```sh
mix run examples/02_review_and_commit/02_03_resolve_out_of_order_edit/run.exs
```

Append `--config /absolute/path/to/reqllm.exs` to use a live model. See the
[ReqLLM configuration](../../00_start_here/00_02_answer_from_memory/README.md#run-with-reqllm).

The trace shows the pending proposal, the correction's Signal ID, the
revision mismatch, and the duplicate decision. The later model input
contains only the corrected resolution.
