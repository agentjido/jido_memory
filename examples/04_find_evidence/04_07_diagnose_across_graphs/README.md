# Diagnose an issue across three graphs

The Agent declares a diagnostic graph operation that checks access to each
named graph before a read.
[Agent definition](run.exs)

Follow a case to its device in the account graph. Use the device ID to
resolve products with the same name. Open the repairs in the experience
graph and select the one tested for the device version. Run the same question
with access to the experience graph denied and check that the Flow skips
that read. The trace shows the graph, subject, and decision at each hop.

Run from `examples/integrations/kg` with the
[TripleStore setup](../../03_store_locations/03_04_reopen_a_kg_store/README.md).

```sh
mix run ../../04_find_evidence/04_07_diagnose_across_graphs/run.exs
```

Add `--config /path/to/reqllm.exs` after the script path for a live model.
