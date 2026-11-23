# Hand off an unfinished case with MemPalace

The receiving Agent declares a MemPalace source with operations to load the
snapshot and open drawers.
[Agent definition](run.exs)

Import three exchanges from a support conversation into MemPalace's SQLite
backend. Build a wake-up snapshot and give the new Agent the drawer references.
It opens the passages about the pending review and confirmed callback. It holds
the requested payment change for confirmation. The trace shows the source path,
drawer ID, and decision for each passage, and the exact messages sent to the
model.

Run `mix deps.get` in the sibling `jido_memory_mempalace` checkout first.
Then run these commands from `examples/integrations/mempalace`.

```sh
mix deps.get
mix run ../../04_find_evidence/04_01_resume_with_mempalace/run.exs
```

The integration uses the sibling `jido_memory_mempalace` checkout. Set
`MEMORY_MEMPALACE_PATH` if it is in another location. Add
`--config /path/to/reqllm.exs` after the script path for a live model.
