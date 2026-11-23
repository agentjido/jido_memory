defmodule SupportDesk.DenyLookup do
  @moduledoc false
  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "scoped_lookup_flow",
    schema: Joi.object(%{}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "requested_lookup", [memory <- context(), inference <- context(:inference)] do
      messages = [
        Context.system("Call lookup_ticket for the requested customer and ticket. The tool checks account access."),
        Context.user("Look up ticket T-17 for customer-b. Call lookup_ticket with customer set to customer-b.")
      ]

      {messages, round} = Inference.tool_round!(inference, messages, ticket_tool(memory))
      {:ok, %{round: round, messages: messages, authorized_scope: memory.agent_id}}
    end

    step "own_lookup",
         [first <- result("requested_lookup"), memory <- context(), inference <- context(:inference)] do
      request = "Use my account instead. Call lookup_ticket for T-17 with customer set to #{memory.agent_id}."

      {_messages, round} =
        Inference.tool_round!(inference, first.messages ++ [Context.user(request)], ticket_tool(memory))

      {:ok, round}
    end

    step "answer", [lookup <- result("own_lookup"), inference <- context(:inference)] do
      %{status: :ok, record: record} = lookup.result

      messages = [
        Context.system("Answer using only the available resolution. Cite the ticket key."),
        Context.user("What happened in my case?\n\nAvailable resolution:\n[#{record.key}] #{record.summary}")
      ]

      {answer, call} = Inference.call!(inference, messages)
      {:ok, %{text: answer, call: call}}
    end

    output(%{
      trace: %{
        authorized_scope: result("requested_lookup", :authorized_scope),
        denied_lookup: result("requested_lookup", :round),
        allowed_lookup: result("own_lookup"),
        answer: result("answer")
      }
    })
  end

  defp ticket_tool(memory) do
    ReqLLM.tool(
      name: "lookup_ticket",
      description: "Recall a ticket resolution if the requested customer matches the active account.",
      parameter_schema: %{
        type: "object",
        properties: %{customer: %{type: "string"}, ticket: %{type: "string"}},
        required: ["customer", "ticket"],
        additionalProperties: false
      },
      callback: fn args -> lookup(memory, args) end
    )
  end

  defp lookup(%{agent_id: customer} = memory, %{"customer" => customer, "ticket" => ticket}) do
    with {:ok, records} <- Memory.recall(memory, :resolutions) do
      case Enum.find(records, &(&1.key == ticket)) do
        nil -> {:ok, %{status: :not_found}}
        record -> {:ok, %{status: :ok, record: %{key: record.key, summary: record.value.summary}}}
      end
    end
  end

  defp lookup(_memory, _args), do: {:ok, %{status: :denied, reason: :scope_mismatch}}
end

defmodule SupportDesk.ScopedLookupAgent do
  @moduledoc false
  use Jido.Agent, name: "scoped_lookup_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}

  memory do
    collection :resolutions, max_entries: 3 do
      schema(Joi.object(%{issue: Joi.string(), summary: Joi.string()}))
    end
  end

  routes do
    signal_source("/examples/memory/01_02_deny_a_lookup")

    route "examples.memory.ticket.resolved", as: :resolve do
      action %{key: key, value: value},
        schema: Joi.object(%{key: Joi.string(), value: Joi.map()}),
        context: context do
        {:ok, context.agent_state, [Memory.remember(:resolutions, key, value)]}
      end
    end

    route "examples.memory.lookup.check", SupportDesk.DenyLookup, as: :ask do
      state(:unchanged)
      reply("examples.memory.lookup.check.answered", from: output(:trace))
    end
  end
end
