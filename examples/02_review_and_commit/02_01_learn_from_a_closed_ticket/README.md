# 02_01 Learn from a closed ticket

A refund event carries a transcript and the processor's confirmed outcome.
The Agent Flow asks the model to propose a resolution and a contact preference.
The review step checks the refund ID, amount, and currency against the event.
The commit step returns a memory Directive for the verified resolution and
holds the email preference in Agent state for confirmation.

```sh
mix run examples/02_review_and_commit/02_01_learn_from_a_closed_ticket/run.exs
```

Append `--config /absolute/path/to/reqllm.exs` to use a live model. See the
[ReqLLM configuration](../../00_start_here/00_02_answer_from_memory/README.md#run-with-reqllm).

The trace includes the proposal input, proposed values, two review decisions,
and the later recall prompt. The recall uses the committed resolution and its
source Signal ID. The pending preference stays out of the model's later input.
