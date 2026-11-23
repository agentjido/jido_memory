# 02_04 Recover a write after a lost acknowledgement

The Agent declares the Ecto resolution table as the source for later reads.
[Agent definition](agent.exs)

A live Agent commits one pending request to its Jido checkpoint. The host
applies the request to two separate SQL tables in one Ecto transaction. One
table holds the resolution and the other holds the operation receipt.

The runner stops the Agent after the transaction and before sending the
acknowledgement. It activates the same Agent address, restores the pending
request, and retries it. The adapter returns the existing receipt. The
runner sends that receipt to the Agent and reads the resolution on a later
Turn. The trace links all these events by request ID.

## Run

From the Jido Memory package root, run these commands.

```sh
cd examples/integrations/ecto
mix deps.get
mix run ../../02_review_and_commit/02_04_recover_a_lost_acknowledgement/run.exs
```

The default run creates and cleans up a temporary SQLite database. For
PostgreSQL, create an empty test database and set `MEMORY_POSTGRES_URL` to
its connection URL. Keep that value in the environment.

```sh
MEMORY_ECTO_DRIVER=postgres mix run ../../02_review_and_commit/02_04_recover_a_lost_acknowledgement/run.exs
```

Append `--config /absolute/path/to/reqllm.exs` to use a live model. See the
[ReqLLM configuration](../../00_start_here/00_02_answer_from_memory/README.md#run-with-reqllm).

This example uses a one-entry outbox in Agent state. The runner drives the
host writer and the acknowledgement Turn. Each run checks one stored record,
one receipt, a rejected request ID with a different payload, and the exact
resolution sent to the model.
