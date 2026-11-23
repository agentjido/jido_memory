# Import a project and navigate its rooms

The Agent declares a MemPalace project source with taxonomy and search
operations.
[Agent definition](run.exs)

Import two files that both use the term “callback token”. Browse the
MemPalace wing, halls, and rooms. Search both rooms, then apply a billing
room filter. The model receives one excerpt from `billing/callback.md`.

Run from `examples/integrations/mempalace` with the
[SQLite setup](../04_01_resume_with_mempalace/README.md).

```sh
mix run ../../04_find_evidence/04_05_navigate_a_mempalace_project/run.exs
```

Add `--config /path/to/reqllm.exs` after the script path for a live model.
The trace includes both sets of hits, the chosen room, and the model input.
