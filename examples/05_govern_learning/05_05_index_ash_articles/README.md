# Index approved Ash knowledge articles

The Agent declares an AshJido source for published articles and an Arcana
index for the excerpts.
[Agent definition](run.exs)

Use a paginated AshJido Action to read published articles for one tenant.
Index the approved fields in Arcana with the source key and revision. For
each result, use AshJido again to check that the caller can read the current
article and that the indexed revision still matches.

Run from `examples/integrations/ash` with the
[AshJido checkout](../../01_investigation/01_04_read_current_account/README.md)
and a [disposable PostgreSQL database with pgvector](../../04_find_evidence/04_03_answer_for_an_exact_release/README.md).

```sh
export MEMORY_ARCANA=1
mix deps.get
mix run ../../05_govern_learning/05_05_index_ash_articles/run.exs
```

Append `--config /absolute/path/to/reqllm.exs` for a live model.

Compare `published`, `withdrawn`, and `revoked` in the JSON trace. The
withdrawn and revoked runs still find the old index entry. Ash denies the
reopen or returns a newer, withdrawn revision. Both model inputs omit the
indexed text. The `pages` field records the tenant-scoped import.
