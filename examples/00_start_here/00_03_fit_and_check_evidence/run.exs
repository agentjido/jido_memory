Code.require_file("../../support/inference.exs", __DIR__)
Code.require_file("agent.exs", __DIR__)

alias SupportDesk.{FitEvidenceAgent, FitEvidenceFixture, Inference}

{params, context} = Inference.agent_config!(System.argv(), FitEvidenceFixture)

resolutions = [
  {"T-09", "Reversed the duplicate invoice"},
  {"T-12", "Cancelled the second payment"},
  {"T-17", "Refunded the second charge"}
]

agent =
  Enum.reduce(resolutions, FitEvidenceAgent.instantiate!(id: "support-desk"), fn {key, summary}, agent ->
    signal = FitEvidenceAgent.resolve_signal!(%{key: key, value: %{issue: "duplicate_charge", summary: summary}})
    {:ok, agent, [_write]} = FitEvidenceAgent.cmd(agent, signal)
    agent
  end)

request = FitEvidenceAgent.request_signal!(Map.put(params, :input, "How did we resolve the last duplicate charge?"))
{:ok, _agent, [%{signal: reply}]} = FitEvidenceAgent.cmd(agent, request, context: context)
trace = reply.data.memory_trace

IO.puts(Jason.encode!(trace, pretty: true))

%{status: :completed, model_calls: 2, output: verified} = reply.data

%{
  evidence: %{
    grant_decision: :allowed,
    selected: [%{key: "T-17", excerpt: ^verified}],
    excluded: [%{key: "T-12"}, %{key: "T-09"}]
  },
  draft: %{rejected: [rejected], verified: [^verified]},
  answer: %{text: ^verified}
} = trace

"[T-17] Waived the late fee" = rejected
[%{role: :system}, %{role: :user, content: "Verified claim:\n" <> ^verified}] = trace.answer.call.model_input

for message <- trace.draft.call.model_input do
  false = String.contains?(message.content, ["T-12", "T-09"])
end
