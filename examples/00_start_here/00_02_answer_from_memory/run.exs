Code.require_file("agent.exs", __DIR__)

alias SupportDesk.{MemoryAgent, MemoryFixture}

{args, []} = OptionParser.parse!(System.argv(), strict: [config: :string])

{model, options, client} =
  case Keyword.fetch(args, :config) do
    :error ->
      {"fixture:repeat-ticket", %{}, MemoryFixture}

    {:ok, path} ->
      {config, _bindings} = Code.eval_file(path)
      {Keyword.fetch!(config, :model), Map.new(Keyword.get(config, :options, [])), Jido.AI.InferenceClient.ReqLLM}
  end

question = "What did we do the last time a customer was charged twice?"
private_note = "Internal ledger follow-up"
agent = MemoryAgent.instantiate!(id: "support-desk")
value = %{issue: "duplicate_charge", summary: "Refunded the second charge", internal_note: private_note}
signal = MemoryAgent.resolve_signal!(%{key: "T-17", value: value})
{:ok, agent, [_write]} = MemoryAgent.cmd(agent, signal)

traces =
  for recall? <- [true, false] do
    request = MemoryAgent.request_signal!(%{input: question, recall: recall?, model: model, options: options})

    {:ok, _agent, [%{signal: reply}]} =
      MemoryAgent.cmd(agent, request, context: %{jido_ai_inference_client: client})

    %{
      recall_enabled: recall?,
      status: reply.data.status,
      answer: reply.data.output,
      reason: reply.data.reason,
      trace: reply.data.memory_trace
    }
  end

json = Jason.encode!(traces, pretty: true)
IO.puts(json)

[%{status: :completed, trace: enabled}, %{status: :completed, trace: disabled}] = traces

%{decision: :allowed, records: [%{key: "T-17", value: %{summary: "Refunded the second charge"} = projected}]} =
  enabled.recall

[:summary] = Map.keys(projected)
%{decision: :disabled, records: []} = disabled.recall
[%{role: :system}, %{role: :user}] = disabled.model_input

[%{role: :user, content: "Memory evidence (retrieved records):\n" <> evidence}] =
  enabled.model_input -- disabled.model_input

[%{"key" => "T-17", "value" => %{"summary" => "Refunded the second charge"}}] = Jason.decode!(evidence)
false = String.contains?(json, private_note)
