# Follow a link across two guides with GraphRAG

The Agent declares an Arcana index for hybrid search and a `:guide_links`
graph for traversal.
[Agent definition](run.exs)

Use the symptom guide and repair guide for the same release. Hybrid search
finds the symptom. GraphRAG finds the same symptom and can reach the repair
through one relationship. The example also checks a zero-hop query and seeds
a different repair in the next release to check collection scope.

Run from `examples/integrations/arcana` with the
[PostgreSQL setup](../04_03_answer_for_an_exact_release/README.md).

```sh
mix run ../../04_find_evidence/04_06_follow_a_guide_link/run.exs
```

Add `--config /path/to/reqllm.exs` after the script path for a live model.
The graph extractors use deterministic fixtures. Arcana stores the entities
and relationship in PostgreSQL and resolves the hop during retrieval.
