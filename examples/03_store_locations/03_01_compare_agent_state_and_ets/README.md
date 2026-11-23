# 03_01 Compare checkpointed Agent state and shared ETS memory

Two Agent definitions use the same reasoning Flow and the same read grant.
One stores its records in Agent state. The other declares a shared ETS
binding with a fixed support scope. The host seeds the shared record and owns
the ETS process. Shared recall runs during a live Agent Turn.

```sh
mix run examples/03_store_locations/03_01_compare_agent_state_and_ets/run.exs
```

Append `--config /absolute/path/to/reqllm.exs` to use a live model. See the
[ReqLLM configuration](../../00_start_here/00_02_answer_from_memory/README.md#run-with-reqllm).

The restored Agent sees its own record. A fresh Agent using state-backed
memory has no records. Two ETS-backed Agents see the same support record.
The first Agent continues without shared evidence if the store times out or
the owner stops. This comparison
uses a fresh AI Session for each call so every prompt shows the effect of
the store. The trace shows each grant decision, the source Signal ID, and
the exact model messages.
