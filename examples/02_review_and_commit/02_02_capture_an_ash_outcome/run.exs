defmodule SupportDesk.CaptureAshOutcome do
  @moduledoc false

  alias Jido.{Joi, Memory}

  use Jido.Flow,
    name: "capture_ash_outcome",
    schema: Joi.object(%{ticket_key: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step("read",
      action: JidoMemory.Examples.Ash.Refunds.Jido.ReadRefund,
      params: %{ticket_key: input(:ticket_key)}
    )

    step "capture", [read <- result("read"), key <- input(:ticket_key)], inline: [context: context] do
      source = read.result
      value = Map.take(source, [:ticket_key, :amount_cents, :currency, :revision])

      with {:ok, prior} <- Memory.recall(context, :resolutions, where: %{ticket_key: key}, limit: 1),
           {:ok, decision, directives} <- capture(prior, key, value) do
        {:ok, %{trace: %{decision: decision, source: value, trigger_signal_id: context.signal.id}}, directives}
      end
    end

    output(result("capture"))
  end

  defp capture([%{value: value}], _key, value), do: {:ok, :already_captured, []}

  defp capture([%{value: %{revision: old}}], _key, %{revision: current}) when current <= old,
    do: {:error, :inconsistent_source_revision}

  defp capture(_prior, key, value), do: {:ok, :captured, [Memory.remember(:resolutions, key, value)]}
end

defmodule SupportDesk.CaptureAshOutcomeAgent do
  @moduledoc false

  use Jido.Agent, name: "capture_ash_outcome_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.Joi

  memory do
    collection :resolutions, max_entries: 8 do
      schema(
        Joi.object(%{
          ticket_key: Joi.string(),
          amount_cents: Joi.integer(),
          currency: Joi.string(),
          revision: Joi.integer()
        })
      )
    end
  end

  routes do
    signal_source("/examples/memory/capture-ash-outcome")

    route "examples.memory.ticket.closed", SupportDesk.CaptureAshOutcome, as: :ticket_closed do
      state(:unchanged)
      reply("examples.memory.outcome.captured", from: output(:trace))
    end
  end
end

alias Jido.Memory
alias JidoMemory.Examples.Ash.Refund
alias SupportDesk.CaptureAshOutcomeAgent, as: Agent

tenant = "north"
admin = [tenant: tenant, actor: %{role: :admin}]
support = [context: %{ash: %{tenant: tenant, actor: %{role: :support}}}]
visitor = [context: %{ash: %{tenant: tenant, actor: %{role: :visitor}}}]
key = "T-17"

source =
  Ash.create!(
    Refund,
    %{ticket_key: key, amount_cents: 2_450, currency: "USD", revision: 1, processor_note: "Internal settlement ID"},
    admin
  )

agent = Agent.instantiate!(id: "north-support")
closed = Agent.ticket_closed_signal!(%{ticket_key: key})
{:ok, captured, effects} = Agent.cmd(agent, closed, support)
{:ok, replayed, replay_effects} = Agent.cmd(captured, closed, support)
{:ok, [first]} = Memory.recall(replayed, :resolutions)

Ash.update!(source, %{amount_cents: 2_550, revision: 2}, admin)
corrected = Agent.ticket_closed_signal!(%{ticket_key: key})
{:ok, updated, update_effects} = Agent.cmd(replayed, corrected, support)
{:ok, [latest]} = Memory.recall(updated, :resolutions)

denied_agent = Agent.instantiate!(id: "north-visitor")
{:error, %{details: %{reason: :forbidden}}} = Agent.cmd(denied_agent, closed, visitor)
{:ok, []} = Memory.recall(denied_agent, :resolutions)

trace_from = fn directives -> Enum.find(directives, &match?(%Jido.Agent.Directive.Reply{}, &1)).signal.data end

trace = %{
  capture: trace_from.(effects),
  replay: trace_from.(replay_effects),
  later_capture: trace_from.(update_effects),
  after_replay: first,
  latest: latest,
  denied: %{decision: :forbidden, records: []}
}

json = Jason.encode!(trace, pretty: true)
IO.puts(json)

original_id = closed.id
corrected_id = corrected.id
%{decision: :captured, source: %{revision: 1}} = trace.capture
%{decision: :already_captured, source: %{revision: 1}, trigger_signal_id: ^original_id} = trace.replay
%{decision: :captured, source: %{revision: 2}} = trace.later_capture
%{key: ^key, source_signal_id: ^original_id, value: %{amount_cents: 2_450, revision: 1}} = first
%{key: ^key, source_signal_id: ^corrected_id, value: %{amount_cents: 2_550, revision: 2}} = latest
false = String.contains?(json, "Internal settlement ID")
