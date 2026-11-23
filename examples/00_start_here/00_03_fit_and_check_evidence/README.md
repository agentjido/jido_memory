# 00_03 Fit and check evidence

Three ticket resolutions match the question. The Flow keeps the newest excerpt
within a 40-byte evidence budget. The question enters through an Agent Signal.
The Flow uses `RecallGranted` to read through the Agent's `:prior_resolutions`
grant. It applies its own budget before it runs `CallModel`. The model returns
a draft that includes a claim about waiving a fee. The Flow checks each line against the
selected evidence and gives the model only the verified line for the revision.
This example uses exact text comparison to make the check reproducible.

```sh
mix run examples/00_start_here/00_03_fit_and_check_evidence/run.exs
```

Append `--config /path/to/reqllm.exs` to use a live model. Use the same
[ReqLLM configuration](../00_02_answer_from_memory/README.md#run-with-reqllm)
as the previous example.

The JSON trace shows the selected excerpt, the excluded tickets, the complete
prepared messages for both calls, and the draft lines the Flow verified and rejected.
The script checks that the reply contains only the verified `T-17` line. The
Flow uses the verified excerpt if the revision is empty or changes the line.
