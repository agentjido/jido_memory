defmodule Jido.Memory.Testing.AgentStateFixture.Agent do
  @moduledoc false

  use Jido.Agent, name: "memory_contract", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}

  memory do
    collection :resolutions, max_entries: 3 do
      schema(Joi.object(%{issue: Joi.string(), summary: Joi.string()}))
    end
  end

  routes do
    signal_source("/memory-contract")

    route "memory.remember", as: :remember do
      action %{entries: entries},
        schema: Joi.object(%{entries: Joi.list(Joi.object(%{key: Joi.string(), value: Joi.map()}))}),
        context: context do
        writes = for %{key: key, value: value} <- entries, do: Memory.remember(:resolutions, key, value)
        {:ok, context.agent_state, writes}
      end
    end

    route "memory.recall", as: :recall do
      action %{where: where, limit: limit},
        schema: Joi.object(%{where: Joi.map(), limit: Joi.integer()}),
        output_schema: Joi.object(%{records: Joi.list(Joi.map())}),
        context: context do
        with {:ok, records} <- Memory.recall(context, :resolutions, where: where, limit: limit) do
          {:ok, %{records: Enum.map(records, &Map.take(&1, [:key, :value, :source_signal_id]))}}
        end
      end

      state(:unchanged)
      reply("memory.recalled", from: output())
    end

    route "memory.forget", as: :forget do
      action %{key: key}, schema: Joi.object(%{key: Joi.string()}), context: context do
        {:ok, context.agent_state, [Memory.forget(:resolutions, key)]}
      end
    end
  end
end

defmodule Jido.Memory.Testing.AgentStateFixture do
  @moduledoc false

  @behaviour Jido.Memory.Testing.MemoryCase

  alias Jido.Agent.Directive.Reply
  alias Jido.Memory.Testing.AgentStateFixture.Agent
  alias Jido.Persistence

  @impl true
  def open(_context, scope), do: {:ok, Agent.instantiate!(id: Atom.to_string(scope))}

  @impl true
  def remember(agent, key, value) do
    remember_batch(agent, [%{key: key, value: value}])
  end

  def remember_batch(agent, entries) do
    signal = Agent.remember_signal!(%{entries: entries})

    with {:ok, next, _directives} <- Agent.cmd(agent, signal) do
      {:ok, next, signal.id}
    end
  end

  @impl true
  def recall(agent, opts) do
    signal = Agent.recall_signal!(%{where: Keyword.get(opts, :where, %{}), limit: Keyword.fetch!(opts, :limit)})

    with {:ok, _next, [%Reply{signal: %{data: %{records: records}}}]} <- Agent.cmd(agent, signal) do
      {:ok, records}
    end
  end

  @impl true
  def forget(agent, key) do
    with {:ok, next, _directives} <- Agent.cmd(agent, Agent.forget_signal!(%{key: key})) do
      {:ok, next}
    end
  end

  @impl true
  def restart(agent) do
    with {:ok, snapshot} <- Persistence.snapshot(agent), do: Persistence.restore(snapshot)
  end
end
