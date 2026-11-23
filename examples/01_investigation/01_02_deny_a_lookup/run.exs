Code.require_file("../../support/inference.exs", __DIR__)
Code.require_file("agent.exs", __DIR__)

defmodule SupportDesk.DenyLookupExample do
  @moduledoc false

  alias Jido.Memory
  alias SupportDesk.ScopedLookupAgent, as: Agent
  alias SupportDesk.Inference

  @private_summary "Credited a private account fee"

  defp fixture(model, prompt, options) do
    if options[:tools] == [] do
      Inference.fixture_reply(model, prompt, "[T-17] Refunded the second charge")
    else
      %{content: [%{text: text}]} = List.last(prompt.messages)
      [_, customer] = Regex.run(~r/customer set to (customer-[ab])/, text)
      Inference.fixture_tool_call(model, prompt, "lookup_ticket", %{"customer" => customer, "ticket" => "T-17"})
    end
  end

  def run(argv) do
    inference = Inference.from_args!(argv, &fixture/3)

    {agent, _} =
      Agent.instantiate!(id: "customer-a")
      |> remember_resolution!("T-17", "duplicate_charge", "Refunded the second charge")

    {other_agent, other_signal} =
      Agent.instantiate!(id: "customer-b")
      |> remember_resolution!("T-17", "duplicate_charge", @private_summary)

    {:ok, [%{key: "T-17", value: %{summary: @private_summary}}]} = Memory.recall(other_agent, :resolutions)
    question = Agent.ask_signal!(%{})
    {:ok, _, [%{signal: reply}]} = Agent.cmd(agent, question, context: %{inference: inference})
    trace = reply.data
    json = Jason.encode!(trace, pretty: true)
    IO.puts(json)

    %{denied_lookup: %{request: %{arguments: %{"customer" => "customer-b", "ticket" => "T-17"}}}} = trace
    %{denied_lookup: %{result: %{status: :denied, reason: :scope_mismatch}}} = trace
    %{allowed_lookup: %{result: %{status: :ok, record: %{key: "T-17", summary: "Refunded the second charge"}}}} = trace
    false = String.contains?(json, [@private_summary, other_signal.id])
    true = String.contains?(trace.answer.text, "T-17")
    true = String.contains?(String.downcase(trace.answer.text), "refund")
  end

  defp remember_resolution!(agent, key, issue, summary) do
    signal = Agent.resolve_signal!(%{key: key, value: %{issue: issue, summary: summary}})
    {:ok, agent, [_write]} = Agent.cmd(agent, signal)
    {agent, signal}
  end
end

SupportDesk.DenyLookupExample.run(System.argv())
