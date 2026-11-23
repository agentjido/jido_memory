# 02_02 Capture a confirmed Ash outcome

The Agent declares a typed resolutions collection. A ticket-closed Signal
starts a Flow that reads the refund through AshJido and captures the outcome.
[Agent definition](run.exs)

The generated AshJido Action uses the host's actor and tenant. The Flow writes only the approved fields with the source revision and trigger Signal ID.

From the Jido Memory package root, run these commands.

```sh
cd examples/integrations/ash
mix deps.get
mix run ../../02_review_and_commit/02_02_capture_an_ash_outcome/run.exs
```

Use the same [AshJido checkout and setup](../../01_investigation/01_04_read_current_account/README.md)
as the account example. The Flow checks the committed source directly.

The trace shows the revision 1 capture, the same Signal replayed with one
record, and a new capture of revision 2. The denied actor produces no
memory record. The internal processor note stays outside the capture.
