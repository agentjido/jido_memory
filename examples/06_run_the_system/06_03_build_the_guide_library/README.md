# Build the versioned Jido guide library

The [Agent's indexing route](run.exs) imports guides into one Arcana
collection per package release. It resolves
each Git tag to a commit and stores the guide path, source URL,
and checksum. A new Agent resumes the import after the first completed job.
A repeat run checks the completed jobs and verifies that each indexed guide
has one current document.

Run from `examples/integrations/arcana` with the
[PostgreSQL setup](../../04_find_evidence/04_03_answer_for_an_exact_release/README.md).

```sh
mix run ../../06_run_the_system/06_03_build_the_guide_library/run.exs
```

The fixture makes three local Git tags and a Hex release record. It checks
the comparison, a release with no guides, and a release with no matching
source tag. Append `--config /absolute/path/to/reqllm.exs` for a live model.

## Import the public catalog

Install `git`, `gh`, and `curl`. Use a disposable database for the
[catalog](catalog.tsv) of public packages from JidoRepo revision `0f717ef`.
This run can index thousands of guides and reuse a cache of bare clones.

```sh
export MEMORY_GUIDE_CATALOG=1
export MEMORY_GUIDE_CACHE=/tmp/public-jido-repos
mix run ../../06_run_the_system/06_03_build_the_guide_library/run.exs
```

By default the comparison asks how `jido` releases `2.3.3` and
`3.0.0-beta.3` define Agent state. It reads the Agent guide from each
release. Set `MEMORY_GUIDE_COMPARE` to `package,older,newer` and
`MEMORY_GUIDE_QUESTION` to ask a different question. Set
`MEMORY_GUIDE_PATHS` to `older_guide,newer_guide` to limit the search to
two specified guide paths.

To compare releases that are already indexed, keep `MEMORY_GUIDE_CATALOG=1`
and set `MEMORY_GUIDE_COMPARE_ONLY=1`. Use the same database. This run
needs no Git cache.

The report lists the release totals, missing tags and guides, job failures,
and the number of jobs skipped on the repeat. `comparison.sources` lists
both release citations. `comparison.call.model_input` shows the excerpts
the model received. If the model leaves out a required citation, the Flow
returns both cited excerpts.

Both modes use the deterministic example embedder. Arcana and pgvector
store and retrieve the documents in both modes.

The verified LM Studio run used `max_tokens: 3_072` in the ReqLLM options.
With a 1,024-token limit, the model used its budget while reasoning and
the Flow returned the cited excerpts.

## Verified import

The public catalog run found 79 packages in 39 repositories. It indexed
4,360 guides across 228 releases and skipped all 4,360 jobs on the repeat.
The database had one current document per indexed guide and zero failed
index jobs. The discovery report listed 103 releases without guides,
13 Hex releases without a matching Git tag, and 13 packages without
a release.

LM Studio cited `guides/agents.md` for the `schema:` option in `2.3.3`
and `guides/agents/define-and-instantiate-an-agent.livemd` for the
`state do` block in `3.0.0-beta.3`.
