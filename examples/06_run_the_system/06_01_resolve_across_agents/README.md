# Resolve a case across Agents and sessions

An intake Agent hands a duplicate charge to a resolver Agent. The resolver's
reasoning Flow reads an approved resolution with `RecallForModel` and
includes the current policy and procedure in the model input. It proposes
a record for the closed case. An operator approves the record before the
next case can use it.

Run from the Jido Memory package root.

```sh
mix run examples/06_run_the_system/06_01_resolve_across_agents/run.exs
```

Append `--config /absolute/path/to/reqllm.exs` for a live model.

Compare `first_case` with `next_case`. Each has its own session and handoff
Signal ID. The first model input cites `T-17`. The next input cites `T-18`
and contains the approved receipt `R-18`. The recalled record carries the
approval Signal ID. The trace includes the raw model reply and the answer
the Flow returned.
