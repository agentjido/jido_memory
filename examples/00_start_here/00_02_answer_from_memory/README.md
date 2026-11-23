# 00_02 Answer from memory

The support Agent commits the `T-17` resolution. The runner sends the same
question Signal twice from the same starting Agent state. The Agent binds
`:prior_resolutions` to its reasoning Flow with `memory SupportDesk.AnswerFlow do`.
The grant allows the `:issue` filter, exposes the `:summary` field, and limits
recall to one record.

The Flow runs `ProjectConversation`, `RecallForModel`, and `CallModel` in
order. The first run adds one evidence message with the ticket key and
summary. The second skips recall. Both runs use the same inference client and
print all system and user messages from its prepared request. The recall trace
keeps the source Signal ID with the projected record.

`RecallForModel` allows up to 4,096 bytes for the evidence message by default.
Set `max_evidence_bytes` on the step to change the limit. The recall trace
keeps the granted records and lists records omitted because they exceeded
the byte budget or could not be encoded as JSON.

## Check the reasoning Flow at compilation

An Agent with AI reasoning and memory gets a compiler warning if the root
reasoning Flow has no recognized memory Action or has a clear wiring error.
The warning names the Agent, Flow, and relevant step. For example, give
`CallModel` the context from the recall step.

```elixir
step("model",
  action: CallModel,
  params: %{turn: result("project", :turn), context: result("recall", :context), tools: false}
)
```

An Agent without AI reasoning can use memory through its Actions, FSM, or
statechart and compiles quietly. If an AI Agent uses memory through a custom
Action, a tool, or a different route, add `warn_unwired_reasoning false` to
its `memory` block to turn off this advisory. The existing access checks
still run when the Agent uses memory.

## Run with the fixture

From the package root, run this command.

```sh
mix run examples/00_start_here/00_02_answer_from_memory/run.exs
```

The script prints a JSON array with recall on first and recall off second.
Each result includes the answer or error and the Agent reply's `memory_trace`.
The trace includes `model_input`, `recall`, and `request_digest`. The fixture
selects its answer from the messages it receives. It needs no network
connection or API key.

## Run with ReqLLM

Save one of these configurations in a trusted local `.exs` file. Its final
expression is a keyword list with a ReqLLM `model` spec and optional `options`.
The runner passes the model and options through Jido's ReqLLM inference
client. Use them for generation settings, provider settings, and HTTP timeouts.

### LM Studio

Start the local server. Set `MEMORY_LLM_MODEL` to the model ID shown by the
server. Set `MEMORY_LLM_BASE_URL` if you use a different address.

```elixir
[
  model: %{
    provider: :lmstudio,
    id: System.fetch_env!("MEMORY_LLM_MODEL"),
    base_url: System.get_env("MEMORY_LLM_BASE_URL", "http://127.0.0.1:1234/v1")
  },
  options: [temperature: 0.0, max_tokens: 1_024, receive_timeout: 120_000]
]
```

### OpenAI or an OpenAI-compatible gateway

Set `MEMORY_LLM_MODEL` to a model ID that the endpoint supports. Set
`MEMORY_LLM_BASE_URL` for a gateway, and provide its key through the environment.
This configuration uses the standard `OPENAI_API_KEY` variable.

```elixir
[
  model: %{
    provider: :openai,
    id: System.fetch_env!("MEMORY_LLM_MODEL"),
    base_url: System.get_env("MEMORY_LLM_BASE_URL", "https://api.openai.com/v1")
  },
  options: [receive_timeout: 60_000]
]
```

You can also use a catalog spec such as `model: "openai:gpt-4o-mini"`. For a
gateway with a separate key variable, set `api_key:` in `options` and read the
key from that variable. If the gateway only accepts Chat Completions, add
`extra: %{wire: %{protocol: "openai_chat"}}` to the model spec. This lets you
choose the gateway's request format even when the catalog model uses Responses.

Run the same two recall modes with your configuration.

```sh
mix run examples/00_start_here/00_02_answer_from_memory/run.exs --config /path/to/reqllm.exs
```

The example prints its full prompt because it uses synthetic ticket data.
ReqLLM handles provider-specific request encoding and authentication.

## Model input from the verified runs

The fixture and LM Studio received the same messages. With recall disabled,
the model received these two messages.

```text
system
If there is no message labeled Memory evidence, reply exactly: I don't have a prior resolution in memory.
Otherwise, answer in one short sentence using that evidence and cite the ticket key.

user
What did we do the last time a customer was charged twice?
```

With recall enabled, the same two messages were followed by this message.

```text
user
Memory evidence (retrieved records):
[{"value":{"summary":"Refunded the second charge"},"key":"T-17"}]
```

LM Studio answered “We refunded the second charge, per ticket T-17.” With
recall disabled, it answered “I don't have a prior resolution in memory.”

## Files

- [Support Agent, reasoning Flow, and fixture](agent.exs)
- [Runner and ticket seed](run.exs)
- [Examples ladder](../../../docs/examples-ladder.md)
