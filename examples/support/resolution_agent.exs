defmodule SupportDesk do
  use Jido.Agent, name: "support_desk", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}

  memory do
    collection :resolutions, max_entries: 3 do
      schema(Joi.object(%{issue: Joi.string(), summary: Joi.string()}))
    end
  end

  routes do
    signal_source("/examples/memory/remember-resolution")

    route "examples.memory.ticket.resolved", as: :resolve do
      action %{key: key, value: value},
        schema: Joi.object(%{key: Joi.string(), value: Joi.map()}),
        context: context do
        {:ok, context.agent_state, [Memory.remember(:resolutions, key, value)]}
      end
    end
  end

  def seed_resolution! do
    instantiate!(id: "support-desk")
    |> remember_resolution!("T-17", "duplicate_charge", "Refunded the second charge")
  end

  def remember_resolution!(agent, key, issue, summary) do
    signal = resolve_signal!(%{key: key, value: %{issue: issue, summary: summary}})
    {:ok, agent, [_write]} = cmd(agent, signal)
    {agent, signal}
  end
end
