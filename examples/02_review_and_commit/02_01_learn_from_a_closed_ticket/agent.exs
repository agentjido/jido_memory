defmodule SupportDesk.LearnClosedTicket do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "learn_closed_ticket",
    schema:
      Joi.object(%{
        key: Joi.string(),
        customer: Joi.string(),
        transcript: Joi.string(),
        refund:
          Joi.object(%{
            id: Joi.string(),
            status: Joi.enum([:succeeded, :failed]),
            amount_cents: Joi.integer(gte: 0),
            currency: Joi.string()
          })
      }),
    output_schema: Joi.object(%{state: Joi.map(), trace: Joi.map()})

  flow do
    step "propose",
         [transcript <- input(:transcript), refund <- input(:refund), inference <- context(:inference)] do
      source = Jason.encode!(%{transcript: transcript, refund: refund})

      {text, call} =
        Inference.call!(inference, [
          Context.system("""
          Extract two proposed memories. Return only a JSON object with this shape:
          {"resolution":{"refund_id":"...","amount_cents":0,"currency":"..."},"preference":{"channel":"email"}}
          Copy the refund ID, amount in cents, and currency from the event. If the customer does not name a channel, set channel to null.
          """),
          Context.user("Proposal input:\n#{source}")
        ])

      case Jason.decode(String.trim(text || "")) do
        {:ok, %{"resolution" => resolution, "preference" => preference}} ->
          {:ok, %{resolution: resolution, preference: preference, call: call}}

        _ ->
          {:error, :invalid_memory_proposal}
      end
    end

    step "review", [proposal <- result("propose"), refund <- input(:refund)] do
      {:ok,
       %{resolution: review_resolution(proposal.resolution, refund), preference: review_preference(proposal.preference)}}
    end

    step "commit",
         [
           proposal <- result("propose"),
           review <- result("review"),
           key <- input(:key),
           customer <- input(:customer),
           state <- context(:agent_state),
           signal <- context(:signal)
         ] do
      {resolution, directives} = write_resolution(review.resolution, key)
      {state, preference} = hold_preference(state, review.preference, customer, signal.id)

      trace = %{
        source_signal_id: signal.id,
        model: proposal.call,
        proposed: Map.take(proposal, [:resolution, :preference]),
        review: %{resolution: resolution, preference: preference}
      }

      {:ok, %{state: state, trace: trace}, directives}
    end

    output(result("commit"))
  end

  defp review_resolution(
         %{"refund_id" => id, "amount_cents" => cents, "currency" => currency},
         %{id: id, status: :succeeded, amount_cents: cents, currency: currency}
       ) do
    remainder = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    %{summary: "Refunded #{currency} #{div(cents, 100)}.#{remainder} (#{id})."}
  end

  defp review_resolution(_proposal, _event), do: :unverified

  defp review_preference(%{"channel" => channel}) when channel in ["email", "sms"], do: {:hold, channel}
  defp review_preference(_proposal), do: :unverified

  defp write_resolution(:unverified, _key), do: {:unverified, []}
  defp write_resolution(value, key), do: {:approved, [Memory.remember(:resolutions, key, value)]}

  defp hold_preference(state, {:hold, channel}, customer, source) do
    pending = %{customer: customer, channel: channel, source_signal_id: source}
    {%{state | pending_preference: pending}, :awaiting_confirmation}
  end

  defp hold_preference(state, :unverified, _customer, _source), do: {state, :unverified}
end

defmodule SupportDesk.RecallLearnedResolution do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Action,
    name: "recall_learned_resolution",
    schema: Joi.object(%{question: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  @impl true
  def run(%{question: question}, %{inference: inference} = context) do
    with {:ok, [record]} <- Memory.recall(context, :resolutions, limit: 1) do
      {answer, call} =
        Inference.call!(inference, [
          Context.system("Copy the verified resolution exactly. Output only that line."),
          Context.user("#{question}\nVerified resolution:\n[#{record.key}] #{record.value.summary}")
        ])

      {:ok, %{trace: %{recall: record, answer: answer, call: call}}}
    end
  end
end

defmodule SupportDesk.LearnClosedTicketAgent do
  @moduledoc false
  use Jido.Agent, name: "learn_closed_ticket_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.Joi
  alias SupportDesk.{LearnClosedTicket, RecallLearnedResolution}

  state do
    schema(
      Joi.object(%{
        pending_preference:
          Joi.object(%{customer: Joi.string(), channel: Joi.string(), source_signal_id: Joi.string()})
          |> Joi.nullable()
          |> Joi.default(nil)
      })
    )
  end

  memory do
    collection :resolutions, max_entries: 4 do
      schema(Joi.object(%{summary: Joi.string()}))
    end

    collection :preferences, max_entries: 4 do
      schema(Joi.object(%{channel: Joi.string()}))
    end
  end

  routes do
    signal_source("/examples/memory/closed-ticket")

    route "examples.memory.refund.recorded", LearnClosedTicket, as: :refund_recorded do
      state(from: output(:state))
      reply("examples.memory.refund.reviewed", from: output(:trace))
    end

    route "examples.memory.resolution.ask", RecallLearnedResolution, as: :ask do
      state(:unchanged)
      reply("examples.memory.resolution.answer", from: output(:trace))
    end
  end
end
