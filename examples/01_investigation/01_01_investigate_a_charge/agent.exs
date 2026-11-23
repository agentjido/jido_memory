defmodule SupportDesk.InvestigateCharge do
  @moduledoc false
  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "investigate_charge_flow",
    schema: Joi.object(%{detail: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  @follow_up "Are both charges posted, or is one still pending?"

  flow do
    step "search", [memory <- context(), inference <- context(:inference)] do
      messages = [
        Context.system("Use recall_resolutions before answering. Start with charge set to any."),
        Context.user("My statement shows two charges. Search all charge types with charge set to any.")
      ]

      {messages, round} = Inference.tool_round!(inference, messages, recall_tool(memory))
      {:ok, %{messages: messages, round: round}}
    end

    step "refine",
         [
           memory <- context(),
           detail <- input(:detail),
           search <- result("search"),
           inference <- context(:inference)
         ] do
      messages = search.messages ++ [Context.user(detail)]
      {_messages, round} = Inference.tool_round!(inference, messages, recall_tool(memory))
      {:ok, %{rounds: [search.round, round], result: round.result}}
    end

    step "finish", [refined <- result("refine"), inference <- context(:inference)] do
      {:ok, finish(refined, inference)}
    end

    output(%{trace: result("finish")})
  end

  defp recall_tool(memory) do
    ReqLLM.tool(
      name: "recall_resolutions",
      description: "Find past resolutions by charge status. Use posted, pending, unknown, or any.",
      parameter_schema: %{
        type: "object",
        properties: %{charge: %{type: "string", enum: ["any", "posted", "pending", "unknown"]}},
        required: ["charge"],
        additionalProperties: false
      },
      callback: fn args -> recall(memory, args) end
    )
  end

  defp recall(memory, %{"charge" => charge})
       when charge in ["any", "posted", "pending", "unknown"] do
    filters = if charge == "any", do: %{}, else: %{issue: charge}

    with {:ok, records} <- Memory.recall(memory, :resolutions, where: filters, limit: 3) do
      entries = Enum.map(records, &%{key: &1.key, charge: &1.value.issue, summary: &1.value.summary})
      {:ok, %{status: :ok, filters: filters, records: entries}}
    end
  end

  defp recall(_memory, _args), do: {:ok, %{status: :invalid_filters}}

  defp finish(%{result: %{records: [record]}} = refined, inference) do
    messages = [
      Context.system("Report what happened using only the matching resolution. Cite the ticket key."),
      Context.user(
        "What did we do last time both charges posted?\n\nMatching resolution:\n[#{record.key}] #{record.summary}"
      )
    ]

    {answer, call} = Inference.call!(inference, messages)
    %{rounds: refined.rounds, stop: :one_match, cited_record: record.key, answer: answer, final_call: call}
  end

  defp finish(refined, _inference) do
    %{rounds: refined.rounds, stop: :insufficient_evidence, answer: @follow_up}
  end
end

defmodule SupportDesk.InvestigateChargeAgent do
  @moduledoc false
  use Jido.Agent, name: "investigate_charge_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}

  memory do
    collection :resolutions, max_entries: 3 do
      schema(Joi.object(%{issue: Joi.string(), summary: Joi.string()}))
    end
  end

  routes do
    signal_source("/examples/memory/01_01_investigate_a_charge")

    route "examples.memory.ticket.resolved", as: :resolve do
      action %{key: key, value: value},
        schema: Joi.object(%{key: Joi.string(), value: Joi.map()}),
        context: context do
        {:ok, context.agent_state, [Memory.remember(:resolutions, key, value)]}
      end
    end

    route "examples.memory.charge.investigate", SupportDesk.InvestigateCharge, as: :ask do
      state(:unchanged)
      reply("examples.memory.charge.investigate.answered", from: output(:trace))
    end
  end
end
