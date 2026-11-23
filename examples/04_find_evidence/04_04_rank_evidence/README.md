# Rank evidence from several search paths

The Agent declares an Arcana index with search and listing operations.
[Agent definition](run.exs)

Compare Arcana keyword, vector, and hybrid search with a list ordered by
effective date. The keyword hit is a dashboard label. Vector and hybrid search
find multiple policy revisions. The Flow checks approval, effective dates,
and the source checksum before it sends the current policy to the model.

Run from `examples/integrations/arcana` with the
[PostgreSQL setup](../04_03_answer_for_an_exact_release/README.md).

```sh
mix run ../../04_find_evidence/04_04_rank_evidence/run.exs
```

Add `--config /path/to/reqllm.exs` after the script path for a live model.
The trace shows rank, score, and source decisions for all four search paths.
Only the accepted excerpt appears in the model input.
