# 01_04 Read current account evidence through AshJido

The [Agent's Flow](run.exs) calls the generated AshJido read Action.
The question Signal starts the read and
gives the model the account key, revision, and refund eligibility. The host supplies the
actor and tenant in `context.ash`. The Ash resource applies its read policy
and tenant filter before the Flow selects the evidence.

## Run

From the Jido Memory package root, run these commands.

```sh
cd examples/integrations/ash
mix deps.get
mix run ../../01_investigation/01_04_read_current_account/run.exs
```

The project uses the AshJido checkout under `Jido/jido_adapters/ash_jido`.
Set `ASH_JIDO_PATH` to use another checkout. The example was checked with
AshJido commit `e4374e8` and Jido `3.0.0-beta.3`. The fixture uses Ash's
ETS data layer and takes no database credentials. Append
`--config /absolute/path/to/reqllm.exs` to run with a live model. See the
[ReqLLM configuration](../../00_start_here/00_02_answer_from_memory/README.md#run-with-reqllm).

## Check the trace

- Both tenants use account key `AC-17` with different refund eligibility.
  Each model call receives the current tenant's three approved fields.
- After the first tenant's account changes, a later read cites revision 2.
- The visitor's read returns a forbidden result before the model step.
