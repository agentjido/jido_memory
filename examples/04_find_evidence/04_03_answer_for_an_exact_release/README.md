# Fetch a guide and answer for an exact release

Send the guide paths from two tagged commits to the [Agent's indexing route](run.exs).
The Flow fetches
each guide at its commit, indexes it in its release collection, and reports
the index job ID. A fresh
Agent answers the same question for the two versions and reports a gap for a
third version. The trace includes the commit, path, checksum, retrieved chunk,
and exact prompt for each answer.

Run from `examples/integrations/arcana` with PostgreSQL and the `vector`
extension available. Set `MEMORY_POSTGRES_URL` to an empty disposable database.

```sh
mix deps.get
mix run ../../04_find_evidence/04_03_answer_for_an_exact_release/run.exs
```

Add `--config /path/to/reqllm.exs` after the script path for a live model.
The example uses a deterministic embedder in both modes. It uses Arcana and
pgvector for document storage and search in both modes.
