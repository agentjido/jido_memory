defmodule SupportDesk.ReadCommittedResolution do
  @moduledoc false

  alias Jido.Joi
  alias JidoMemory.Examples.Ecto.MemoryTable

  use Jido.Action, name: "read_committed_resolution", schema: Joi.object(%{ticket_key: Joi.string()})

  @impl true
  def run(%{ticket_key: key}, %{memory_repo: repo, agent_id: owner}) do
    {:ok, %{record: MemoryTable.get(repo, owner, key)}}
  end
end

defmodule SupportDesk.PendingMemoryAgent do
  @moduledoc false
  use Jido.Agent, name: "pending_memory_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}
  alias Jido.Agent.Directive.Reply

  memory do
    source(:committed_resolutions, operations: [read: SupportDesk.ReadCommittedResolution])
  end

  state do
    schema(
      Joi.object(%{
        pending:
          Joi.object(%{
            request_id: Joi.string(),
            agent_id: Joi.string(),
            ticket_key: Joi.string(),
            summary: Joi.string(),
            source_signal_id: Joi.string()
          })
          |> Joi.nullable()
          |> Joi.default(nil),
        acknowledged: Joi.string() |> Joi.nullable() |> Joi.default(nil)
      })
    )
  end

  routes do
    signal_source("/examples/memory/lost-acknowledgement")

    route "examples.memory.store.queue", as: :queue do
      action %{ticket_key: key, summary: summary},
        schema: Joi.object(%{ticket_key: Joi.string(), summary: Joi.string()}),
        context: context do
        request = %{
          request_id: "#{context.agent_id}/#{context.signal.id}/0",
          agent_id: context.agent_id,
          ticket_key: key,
          summary: summary,
          source_signal_id: context.signal.id
        }

        case context.agent_state do
          %{pending: nil} = state ->
            respond(%{state | pending: request}, %{decision: :queued, request: request}, context)

          %{pending: ^request} = state ->
            respond(state, %{decision: :already_queued, request: request}, context)

          _ ->
            {:error, :queue_full}
        end
      end
    end

    route "examples.memory.store.pending", as: :pending do
      action %{}, schema: Joi.object(%{}), context: context do
        respond(context.agent_state, context.agent_state, context)
      end
    end

    route "examples.memory.store.ack", as: :acknowledge do
      action %{request_id: request_id}, schema: Joi.object(%{request_id: Joi.string()}), context: context do
        case context do
          %{memory_writer: true, agent_state: %{pending: %{request_id: ^request_id}} = state} ->
            updated = %{state | pending: nil, acknowledged: request_id}
            respond(updated, %{decision: :acknowledged, request_id: request_id}, context)

          %{memory_writer: true} ->
            {:error, :unexpected_receipt}

          _ ->
            {:error, :writer_required}
        end
      end
    end

    route "examples.memory.store.read", as: :read do
      action %{ticket_key: key}, schema: Joi.object(%{ticket_key: Joi.string()}), context: context do
        with {:ok, result} <- Memory.access(context, :source, :committed_resolutions, :read, %{ticket_key: key}) do
          respond(context.agent_state, result, context)
        end
      end
    end
  end

  defp respond(state, data, context) do
    with {:ok, signal} <- Jido.Agent.build_signal(context, "examples.memory.store.result", data) do
      {:ok, state, [%Reply{signal: signal}]}
    end
  end
end
