Code.require_file("../../support/inference.exs", __DIR__)
Code.require_file("agent.exs", __DIR__)

defmodule SupportDesk.InvestigateChargeExample do
  @moduledoc false

  alias SupportDesk.InvestigateChargeAgent, as: Agent
  alias SupportDesk.Inference

  defp fixture(model, prompt, options) do
    %{content: [%{text: text}]} = List.last(prompt.messages)

    if options[:tools] == [] do
      Inference.fixture_reply(model, prompt, "[T-17] Refunded the second charge")
    else
      [_, charge] = Regex.run(~r/charge set to (any|posted|unknown)/, text)
      Inference.fixture_tool_call(model, prompt, "recall_resolutions", %{"charge" => charge})
    end
  end

  def run(argv) do
    inference = Inference.from_args!(argv, &fixture/3)
    agent = Agent.instantiate!(id: "support-desk")
    agent = remember_resolution!(agent, "T-12", "pending", "Waited for the authorization to expire")
    agent = remember_resolution!(agent, "T-17", "posted", "Refunded the second charge")

    details = [
      "Both charges have posted. Call recall_resolutions again with charge set to posted.",
      "I cannot tell whether the charges posted. Call recall_resolutions again with charge set to unknown."
    ]

    traces =
      Enum.map(details, fn detail ->
        question = Agent.ask_signal!(%{detail: detail})
        {:ok, _, [%{signal: reply}]} = Agent.cmd(agent, question, context: %{inference: inference})
        reply.data
      end)

    IO.puts(Jason.encode!(traces, pretty: true))

    [resolved, ambiguous] = traces
    %{rounds: [broad, narrow], stop: :one_match, cited_record: "T-17"} = resolved
    %{result: %{filters: %{}, records: [_, _]}} = broad
    %{result: %{filters: %{issue: "posted"}, records: [%{key: "T-17"}]}} = narrow
    true = String.contains?(resolved.answer, ["T-17"]) and String.contains?(String.downcase(resolved.answer), "refund")

    %{
      rounds: [_, %{result: %{filters: %{issue: "unknown"}, records: []}}],
      answer: "Are both charges posted, or is one still pending?"
    } = ambiguous
  end

  defp remember_resolution!(agent, key, issue, summary) do
    signal = Agent.resolve_signal!(%{key: key, value: %{issue: issue, summary: summary}})
    {:ok, agent, [_write]} = Agent.cmd(agent, signal)
    agent
  end
end

SupportDesk.InvestigateChargeExample.run(System.argv())
