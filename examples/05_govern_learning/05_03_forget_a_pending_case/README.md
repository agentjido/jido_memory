# Forget a case while work is pending

The Agent declares an Arcana index with deletion and tombstone operations and
a collection for case summaries.
[Agent definition](run.exs)

Index a case in Arcana and store an Agent summary. Queue a delayed write.
Delete the document, chunks, graph entity, and summary. The deletion writes
a PostgreSQL tombstone under the same case lock that the index worker uses.
Release the delayed write, restart the worker, and send the write again.
The trace shows both refusals, the remaining counts, and what the model saw.

Run from `examples/integrations/arcana` with the
[PostgreSQL setup](../../04_find_evidence/04_03_answer_for_an_exact_release/README.md).

```sh
mix run ../../05_govern_learning/05_03_forget_a_pending_case/run.exs
```

Add `--config /path/to/reqllm.exs` after the script path for a live model.
