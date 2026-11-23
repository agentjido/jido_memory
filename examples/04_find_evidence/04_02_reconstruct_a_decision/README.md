# Reconstruct a decision as of two dates

The Agent declares a `:dated_facts` graph backed by the MemPalace query
Action.
[Agent definition](run.exs)

End an account fact in MemPalace and add its replacement. Then record a
retroactive correction and a new policy. MemPalace filters by effective date.
The Flow selects the version that was on record on the requested knowledge date.
The trace shows both dates, the selected versions, and the citations supplied
to the model.

Run from `examples/integrations/mempalace` after the
[MemPalace dependency setup](../04_01_resume_with_mempalace/README.md).

```sh
mix run ../../04_find_evidence/04_02_reconstruct_a_decision/run.exs
```

Add `--config /path/to/reqllm.exs` after the script path for a live model.
See the [handoff example](../04_01_resume_with_mempalace/README.md) for setup.
