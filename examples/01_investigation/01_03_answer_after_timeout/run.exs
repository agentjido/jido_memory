Code.require_file("../../support/inference.exs", __DIR__)
Code.require_file("agent.exs", __DIR__)

defmodule SupportDesk.AnswerAfterTimeoutExample do
  @moduledoc false

  alias SupportDesk.PolicyTimeoutAgent, as: Agent
  alias SupportDesk.Inference

  defp fixture(model, prompt, _options) do
    [_, %{content: [%{text: text}]}] = prompt.messages
    Inference.fixture_reply(model, prompt, String.replace_prefix(text, "Verified claim:\n", ""))
  end

  def run(argv) do
    inference = Inference.from_args!(argv, &fixture/3)
    agent = Agent.instantiate!(id: "support-desk")
    agent = remember_resolution!(agent, "T-17", "duplicate_charge", "Refunded the second charge")

    question = Agent.ask_signal!(%{})
    {:ok, _, [%{signal: reply}]} = Agent.cmd(agent, question, context: %{inference: inference}, max_concurrency: 2)
    trace = reply.data
    IO.puts(Jason.encode!(trace, pretty: true))

    [history, policy] = trace.sources
    %{value: %{record: %{key: "T-17"}}} = history
    %{value: %{attempts: [%{attempt: 1, status: :timeout}, %{attempt: 2, status: :timeout}]}} = policy
    %{recommendation: %{status: :deferred, reason: :policy_unavailable}} = trace
    "[T-17] Refunded the second charge\n" <> "I need the current policy before I can recommend a refund." = trace.answer
  end

  defp remember_resolution!(agent, key, issue, summary) do
    signal = Agent.resolve_signal!(%{key: key, value: %{issue: issue, summary: summary}})
    {:ok, agent, [_write]} = Agent.cmd(agent, signal)
    agent
  end
end

SupportDesk.AnswerAfterTimeoutExample.run(System.argv())
