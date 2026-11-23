Code.require_file("../../support/inference.exs", __DIR__)
Code.require_file("agent.exs", __DIR__)

defmodule SupportDesk.ClosedTicketExample do
  @moduledoc false

  alias Jido.Memory
  alias SupportDesk.Inference
  alias SupportDesk.LearnClosedTicketAgent, as: Agent

  def run(argv) do
    context = %{inference: Inference.from_args!(argv, &fixture/3)}
    agent = Agent.instantiate!(id: "support-desk")

    ticket = %{
      key: "T-17",
      customer: "customer-a",
      transcript: "Customer: Please email my refund receipt.\nSupport: I will record your refund now.",
      refund: %{id: "R-17", status: :succeeded, amount_cents: 2450, currency: "USD"}
    }

    closed = Agent.refund_recorded_signal!(ticket)
    {:ok, committed, directives} = Agent.cmd(agent, closed, context: context)
    review = Enum.find(directives, &match?(%Jido.Agent.Directive.Reply{}, &1)).signal.data
    question = Agent.ask_signal!(%{question: "What did we do for ticket T-17?"})
    {:ok, _agent, [%{signal: reply}]} = Agent.cmd(committed, question, context: context)

    {:ok, []} = Memory.recall(agent, :resolutions)
    {:ok, []} = Memory.recall(committed, :preferences)
    pending = committed.state.pending_preference
    source = closed.id

    trace = %{capture: review, pending_preference: pending, later_turn: reply.data}
    IO.puts(Jason.encode!(trace, pretty: true))

    %{source_signal_id: ^source, review: %{resolution: :approved, preference: :awaiting_confirmation}} = review
    %{customer: "customer-a", channel: "email", source_signal_id: ^source} = pending
    %{recall: %{key: "T-17", source_signal_id: ^source}, answer: answer} = reply.data
    "[T-17] Refunded USD 24.50 (R-17)." = String.trim(answer)
    false = Enum.any?(reply.data.call.model_input, &String.contains?(&1.content, ["email", "customer-a"]))
  end

  defp fixture(model, prompt, _options) do
    %{content: [%{text: text}]} = List.last(prompt.messages)

    answer =
      case text do
        "Proposal input:\n" <> json ->
          %{"transcript" => transcript, "refund" => refund} = Jason.decode!(json)
          channel = if String.contains?(transcript, "email"), do: "email", else: nil

          Jason.encode!(%{
            resolution: %{
              refund_id: refund["id"],
              amount_cents: refund["amount_cents"],
              currency: refund["currency"]
            },
            preference: %{channel: channel}
          })

        question ->
          question |> String.split("\nVerified resolution:\n", parts: 2) |> List.last()
      end

    Inference.fixture_reply(model, prompt, answer)
  end
end

SupportDesk.ClosedTicketExample.run(System.argv())
