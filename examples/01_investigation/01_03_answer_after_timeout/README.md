# 01_03 Answer after a source timeout

The [Agent](agent.exs) declares a `:resolutions` collection and records
`T-17` on a ticket Signal. A question Signal starts parallel reads from that
collection and a synthetic policy source.
History returns `T-17`. The policy source exceeds its deadline twice. The
Flow cancels each timed-out request and gives the model the historical
resolution. The final reply reports the prior refund and defers a new refund
recommendation until current policy is available.

```sh
mix run examples/01_investigation/01_03_answer_after_timeout/run.exs
```

Append `--config /path/to/reqllm.exs` to use a live model. Use the
[ReqLLM configuration](../../00_start_here/00_02_answer_from_memory/README.md#run-with-reqllm).

The JSON trace shows both source outcomes, the two timeout attempts, the model
input and reply, and the Flow's recommendation decision. If the model returns
an empty or changed line, the Flow uses the verified historical excerpt.
