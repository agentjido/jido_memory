# 01_02 Deny a lookup and continue

The [Agent](agent.exs) declares a `:resolutions` collection. Two instances
each store a resolution under ticket key `T-17`. The question Signal starts
a Turn on one instance. The tool checks the requested customer against the
Agent ID in the Turn context before it calls `Memory.recall/3`.

The model first requests the other customer's ticket. It receives
`scope_mismatch`. The model then requests the active customer's ticket and
answers from the allowed resolution. The script checks that the other
customer's summary and source Signal ID are absent from the complete trace.

```sh
mix run examples/01_investigation/01_02_deny_a_lookup/run.exs
```

Append `--config /path/to/reqllm.exs` to use a live model that supports tool
calling. Use the [ReqLLM configuration](../../00_start_here/00_02_answer_from_memory/README.md#run-with-reqllm).

Read `authorized_scope`, `denied_lookup`, and `allowed_lookup` in the JSON
trace. The final model call receives the allowed excerpt.
