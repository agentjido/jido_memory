Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.RevisionReviewAgent do
  @moduledoc false

  use Jido.Agent, name: "revision_review_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}
  alias Jido.Agent.Directive.Reply
  alias ReqLLM.Context
  alias SupportDesk.Inference

  state do
    schema(
      Joi.object(%{
        proposal:
          Joi.object(%{
            ticket_key: Joi.string(),
            source_signal_id: Joi.string(),
            expected_revision: Joi.integer(),
            summary: Joi.string(),
            status: Joi.enum([:pending, :stale, :approved])
          })
          |> Joi.nullable()
          |> Joi.default(nil)
      })
    )
  end

  memory do
    collection :resolutions, max_entries: 4 do
      schema(Joi.object(%{ticket_key: Joi.string(), revision: Joi.integer(), summary: Joi.string()}))
    end
  end

  routes do
    signal_source("/examples/memory/revision-review")

    route "examples.memory.resolution.propose", as: :propose do
      action %{key: key, note: note}, schema: Joi.object(%{key: Joi.string(), note: Joi.string()}), context: context do
        propose(key, note, context)
      end
    end

    route "examples.memory.resolution.correct", as: :correct do
      action %{key: key, expected_revision: expected, summary: summary},
        schema: Joi.object(%{key: Joi.string(), expected_revision: Joi.integer(), summary: Joi.string()}),
        context: context do
        with %{operator: true} <- context,
             {:ok, record} <- active_record(context, key),
             ^expected <- revision(record) do
          write(key, expected + 1, summary, :corrected, context.agent_state, context)
        else
          {:error, _} = error -> error
          actual when is_integer(actual) -> {:error, :stale_correction}
          _ -> {:error, :operator_required}
        end
      end
    end

    route "examples.memory.resolution.approve", as: :approve do
      action %{source_signal_id: source},
        schema: Joi.object(%{source_signal_id: Joi.string()}),
        context: context do
        approve(source, context)
      end
    end

    route "examples.memory.resolution.ask", as: :ask do
      action %{key: key}, schema: Joi.object(%{key: Joi.string()}), context: context do
        with {:ok, %{value: value} = record} <- active_record(context, key) do
          {answer, call} =
            Inference.call!(context.inference, [
              Context.system("Copy the current resolution exactly. Output only that line."),
              Context.user("Current resolution:\n[#{key} rev #{value.revision}] #{value.summary}")
            ])

          respond(context.agent_state, %{answer: answer, record: record, call: call}, context)
        else
          {:ok, nil} -> {:error, :resolution_not_found}
          {:error, _} = error -> error
        end
      end
    end
  end

  defp propose(key, note, %{agent_state: state, signal: signal} = context) do
    case state.proposal do
      %{source_signal_id: id} when id == signal.id ->
        respond(state, %{decision: :duplicate_capture, source_signal_id: id, model_calls: 0}, context)

      _ ->
        with {:ok, record} <- active_record(context, key) do
          {proposal_text, call} =
            Inference.call!(context.inference, [
              Context.system("Copy the proposed resolution exactly. Output only that line."),
              Context.user("Proposed resolution:\n#{note}")
            ])

          proposal = %{
            ticket_key: key,
            source_signal_id: signal.id,
            expected_revision: revision(record),
            summary: String.trim(proposal_text || ""),
            status: :pending
          }

          respond(%{state | proposal: proposal}, %{decision: :pending_review, proposal: proposal, call: call}, context)
        end
    end
  end

  defp approve(source, %{operator: true, agent_state: state} = context) do
    with %{source_signal_id: ^source, status: :pending} = proposal <- state.proposal,
         {:ok, record} <- active_record(context, proposal.ticket_key) do
      current = revision(record)

      if current == proposal.expected_revision do
        state = %{state | proposal: %{proposal | status: :approved}}
        write(proposal.ticket_key, current + 1, proposal.summary, :approved, state, context)
      else
        trace = %{
          decision: :stale_proposal,
          expected_revision: proposal.expected_revision,
          active_revision: current,
          active_source_signal_id: record && record.source_signal_id
        }

        respond(%{state | proposal: %{proposal | status: :stale}}, trace, context)
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :proposal_not_pending}
    end
  end

  defp approve(_source, _context), do: {:error, :operator_required}

  defp active_record(context, key) do
    with {:ok, records} <- Memory.recall(context, :resolutions, where: %{ticket_key: key}, limit: 1) do
      {:ok, List.first(records)}
    end
  end

  defp revision(nil), do: 0
  defp revision(record), do: record.value.revision

  defp write(key, revision, summary, decision, state, context) do
    value = %{ticket_key: key, revision: revision, summary: summary}
    trace = %{decision: decision, source_signal_id: context.signal.id, value: value}
    respond(state, trace, context, [Memory.remember(:resolutions, key, value)])
  end

  defp respond(state, trace, context, effects \\ []) do
    with {:ok, reply} <- Jido.Agent.build_signal(context, "examples.memory.revision.result", trace) do
      {:ok, state, effects ++ [%Reply{signal: reply}]}
    end
  end
end

alias SupportDesk.Inference
alias SupportDesk.RevisionReviewAgent, as: Agent

fixture = fn model, prompt, _options ->
  %{content: [%{text: text}]} = List.last(prompt.messages)
  line = text |> String.split("\n", parts: 2) |> List.last()
  Inference.fixture_reply(model, prompt, line)
end

inference = Inference.from_args!(System.argv(), fixture)
operator = [context: %{operator: true}]
model_context = [context: %{inference: inference}]

send_signal = fn agent, signal, opts ->
  {:ok, next, effects} = Agent.cmd(agent, signal, opts)
  {next, Enum.find(effects, &match?(%Jido.Agent.Directive.Reply{}, &1)).signal.data}
end

key = "T-17"
initial = Agent.correct_signal!(%{key: key, expected_revision: 0, summary: "Refund request pending."})
original = Agent.propose_signal!(%{key: key, note: "Refund sent to original card."})
correction = Agent.correct_signal!(%{key: key, expected_revision: 1, summary: "Refund failed. Replacement issued."})
review = Agent.approve_signal!(%{source_signal_id: original.id})

{initial_agent, _} = send_signal.(Agent.instantiate!(id: "support-desk"), initial, operator)
{pending, proposal} = send_signal.(initial_agent, original, model_context)
{corrected, edit} = send_signal.(pending, correction, operator)
{reviewed, stale} = send_signal.(corrected, review, operator)
{replayed, duplicate} = send_signal.(reviewed, original, [])
{_, answer} = send_signal.(replayed, Agent.ask_signal!(%{key: key}), model_context)

trace = %{proposal: proposal, correction: edit, review: stale, redelivery: duplicate, later_turn: answer}
IO.puts(Jason.encode!(trace, pretty: true))

source = correction.id
%{proposal: %{expected_revision: 1, status: :pending}} = proposal
%{decision: :stale_proposal, expected_revision: 1, active_revision: 2, active_source_signal_id: ^source} = stale
%{decision: :duplicate_capture, model_calls: 0} = duplicate
%{value: %{revision: 2}, source_signal_id: ^source} = answer.record
"[T-17 rev 2] Refund failed. Replacement issued." = String.trim(answer.answer)
false = Enum.any?(answer.call.model_input, &String.contains?(&1.content, "Refund sent to original card."))
