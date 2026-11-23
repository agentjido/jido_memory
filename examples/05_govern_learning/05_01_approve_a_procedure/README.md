# Turn case history into an approved procedure

Ask the model to propose a rule from two case outcomes. Replay a held-out case
with missing policy. An operator corrects the failed rule and approves the
revision after another replay. The next model call cites revision 2 and asks
for current policy. The trace keeps the draft, both replays, and the model input.

```sh
mix run examples/05_govern_learning/05_01_approve_a_procedure/run.exs
```

Add `--config /path/to/reqllm.exs` after the script path for a live model.
If the model produces no Boolean proposal, the script uses the example's
baseline rule and records that decision in the trace.
