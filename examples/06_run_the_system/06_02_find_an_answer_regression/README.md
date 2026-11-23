# Find the cause of an answer regression

The Agent declares an Arcana index, a link graph, and a collection of approved
procedures.
[Agent definition](run.exs)

Run the same repair question with recall disabled, hybrid retrieval, and
GraphRAG with an approved procedure. Run the graph case again with its
retrieval depth set to zero. The symptom still reaches the model. The
repair and its procedure stay out of the prompt.

Run from `examples/integrations/arcana` with the
[PostgreSQL setup](../../04_find_evidence/04_03_answer_for_an_exact_release/README.md).

```sh
mix run ../../06_run_the_system/06_02_find_an_answer_regression/run.exs
```

Append `--config /absolute/path/to/reqllm.exs` for a live model.

Compare `first_divergence` and `cases` in the JSON. Each case records the
retrieval settings, exact model input, task score, citation accuracy,
and elapsed time. `call.usage` contains the token counts when the provider
reports them.
