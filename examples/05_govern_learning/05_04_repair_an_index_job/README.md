# Repair a failed Arcana index job

The Agent runs Arcana Actions to check the job, retry it, and search the index.
[Agent definition](run.exs)

Force an embedding failure for one guide. Stop the first import after two
jobs. A fresh Agent reads the failed job, retries it, skips the guide that
was already indexed, and processes the deferred guide. Repeat the import
and check one completed document per guide. The answer cites the repaired
guide in its release collection.

Run from `examples/integrations/arcana` with the
[PostgreSQL setup](../../04_find_evidence/04_03_answer_for_an_exact_release/README.md).

```sh
mix run ../../05_govern_learning/05_04_repair_an_index_job/run.exs
```

Add `--config /path/to/reqllm.exs` after the script path for a live model.
