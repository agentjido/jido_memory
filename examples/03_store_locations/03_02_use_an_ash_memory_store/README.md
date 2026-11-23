# 03_02 Use an Ash resource as a memory store

The Agent binds a collection to four AshJido-generated Actions for put,
get, query, and delete. The same model-facing recall step used for Agent
state and ETS reads from Ash. Ash checks the host-supplied actor and tenant.

From the Jido Memory package root, run these commands.

```sh
cd examples/integrations/ash
mix deps.get
mix run ../../03_store_locations/03_02_use_an_ash_memory_store/run.exs
```

Use the same [AshJido checkout and setup](../../01_investigation/01_04_read_current_account/README.md)
as the account example. Append `--config /absolute/path/to/reqllm.exs` to
use a live model.

Each actor reads a distinct `T-17` from its tenant. Ash denies a mismatched
actor and tenant. The Agent stages a write with an actor ID and a tenant.
The host resolves the actor again at commit. After write access is revoked,
Ash denies the pending write and the record stays absent. The actor can read
the existing record until the host also revokes read access.

The trace shows the four recall prompts, the pending actor and tenant,
and the commit decision. Each recall starts a fresh AI Session. The fixture
uses the Ash ETS data layer and drives the pending write from the host.
