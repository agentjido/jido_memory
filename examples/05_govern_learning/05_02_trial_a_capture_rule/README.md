# Trial a new capture rule in shadow mode

Run the active rule and the shadow rule on the same confirmed and pending
Signals. The active rule stores the confirmed resolution. The shadow rule
would also store the verified reason. Compare two inference calls and check
that the extra field exists only in the evaluation input.

```sh
mix run examples/05_govern_learning/05_02_trial_a_capture_rule/run.exs
```

Add `--config /path/to/reqllm.exs` after the script path for a live model.
