# 03_03 Reject a stale result from an external adapter

The same Flow reads a candidate from Agent state and from a host-supplied
adapter. The adapter uses a real ETS table, following the Basic-over-ETS
test pattern from the Mem0 package. It contains an older ticket revision.

Before the model call, the Flow checks the candidate against the host's
source revision. Revision 2 passes. Revision 1 stays out of the prompt.
The trace keeps the candidate's key, source Signal ID, and revision.
The runner checks the final answer against the verified result and uses
the verified line if the model changes it. The trace includes the model's
actual text and the output decision.

```sh
mix run examples/03_store_locations/03_03_reject_a_stale_adapter_result/run.exs
```

Append `--config /absolute/path/to/reqllm.exs` to use a live model. See the
[ReqLLM configuration](../../00_start_here/00_02_answer_from_memory/README.md#run-with-reqllm).
