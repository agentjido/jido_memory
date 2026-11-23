Code.require_file("../../support/inference.exs", __DIR__)
Code.require_file("../../00_start_here/00_02_answer_from_memory/agent.exs", __DIR__)

defmodule SupportDesk.AshMemoryAgent do
  @moduledoc false
  use Jido.Agent, name: "ash_memory_agent", plugins: [Jido.AI.Agent.Plugin, Jido.Memory.Plugin]

  import Jido.AI.Agent.Plugin, only: [ai: 1, reasoning: 2]

  alias Jido.Joi
  alias Jido.Memory.Store.Ash, as: AshStore
  alias JidoMemory.Examples.Ash.MemoryRecords.Jido, as: Actions
  alias SupportDesk.AnswerFlow

  @binding %{
    put: Actions.PutMemory,
    get: Actions.GetMemory,
    query: Actions.QueryMemory,
    delete: Actions.DeleteMemory,
    filter_fields: [:summary]
  }

  state do
    schema(
      Joi.object(%{
        session: Jido.AI.Thread.Projection.schema(),
        pending: Joi.map() |> Joi.nullable() |> Joi.default(nil)
      })
    )
  end

  ai do
    reasoning AnswerFlow do
      instructions("""
      If there is no message labeled Memory evidence, reply exactly: I don't have a prior resolution in memory.
      Otherwise, copy the summary exactly and cite the ticket key.
      """)
    end
  end

  memory AnswerFlow do
    external_collection :resolutions, store: {AshStore, @binding} do
      schema(Joi.object(%{summary: Joi.string()}))
    end

    read(:prior_resolutions, collection: :resolutions, filters: [:summary], expose: [:summary], limit: 1)
  end

  routes do
    signal_source("/examples/memory/ash-store")

    route "examples.memory.ash.stage", as: :stage do
      action %{key: key, summary: summary},
        schema: Joi.object(%{key: Joi.string(), summary: Joi.string()}),
        context: context do
        case context do
          %{ash: %{actor: %{id: id, may_write: true, tenant: tenant}, tenant: tenant}} ->
            record = %{key: key, value: %{summary: summary}, source_signal_id: context.signal.id}
            pending = %{actor_id: id, tenant: tenant, record: record}
            {:ok, %{context.agent_state | pending: pending}}

          _ ->
            {:error, :writer_required}
        end
      end
    end
  end

  def binding, do: @binding
end

defmodule SupportDesk.AshStoreExample do
  @moduledoc false

  alias Jido.{AgentServer, Session, Signal}
  alias Jido.Memory.Store.Ash, as: AshStore
  alias SupportDesk.{AshMemoryAgent, Inference, MemoryFixture}

  @instance SupportDesk.AshMemoryInstance

  def run(argv) do
    {params, context} = Inference.agent_config!(argv, MemoryFixture)
    params = Map.merge(params, %{input: "What is the latest resolution for this account?", where: %{}})

    actors = %{
      "alex" => %{id: "alex", tenant: "north", may_read: true, may_write: true},
      "bea" => %{id: "bea", tenant: "south", may_read: true, may_write: true}
    }

    binding = AshMemoryAgent.binding()
    north = scope(actors, "alex")
    south = scope(actors, "bea")

    north_record = seed!(binding, north, "T-17", "Refunded the second charge")
    south_record = seed!(binding, south, "T-17", "Waited for the pending charge to expire")
    seed!(binding, south, "T-deleted", "Removed obsolete draft")
    :ok = AshStore.delete(binding, :resolutions, "T-deleted", south)
    {:ok, nil} = AshStore.get(binding, :resolutions, "T-deleted", south)
    {:ok, ^north_record} = AshStore.get(binding, :resolutions, "T-17", north)
    {:ok, ^south_record} = AshStore.get(binding, :resolutions, "T-17", south)
    newest = seed!(binding, north, "T-filter", "Reviewed another charge")
    {:ok, [^newest]} = AshStore.recall(binding, :resolutions, %{}, 1, north)
    {:ok, [^north_record]} = AshStore.recall(binding, :resolutions, north_record.value, 1, north)
    {:ok, []} = AshStore.recall(binding, :resolutions, north_record.value, 1, south)
    {:error, {:unsupported_store_filter, :key}} = AshStore.recall(binding, :resolutions, %{key: "T-17"}, 1, north)
    :ok = AshStore.delete(binding, :resolutions, "T-filter", north)
    mismatched_scope = put_in(north.ash.tenant, "south")
    {:error, :forbidden} = AshStore.get(binding, :resolutions, "T-17", mismatched_scope)
    {:error, :forbidden} = AshStore.put(binding, :resolutions, north_record, mismatched_scope)

    stage = AshMemoryAgent.stage_signal!(%{key: "T-18", summary: "Unapproved refund"})
    definition = AshMemoryAgent.instantiate!(id: "north-support")
    {:ok, pending_agent, []} = AshMemoryAgent.cmd(definition, stage, context: north)
    pending = pending_agent.state.pending
    %{actor_id: "alex", tenant: "north"} = pending

    {:ok, instance} = Jido.start_link(name: @instance)

    try do
      {:ok, primary} = Jido.start_agent(@instance, pending_agent)
      {:ok, secondary} = Jido.start_agent(@instance, AshMemoryAgent, id: "south-support")
      first = ask!(primary, %{params | where: north_record.value}, context, north)
      second = ask!(secondary, params, context, south)

      revoked = put_in(actors["alex"].may_write, false)
      resolved = scope(revoked, pending.actor_id)
      %{ash: %{tenant: tenant}} = resolved
      ^tenant = pending.tenant
      {:error, :forbidden} = AshStore.put(binding, :resolutions, pending.record, resolved)
      {:ok, nil} = AshStore.get(binding, :resolutions, "T-18", resolved)
      retained = ask!(primary, params, context, resolved)

      blocked = put_in(revoked["alex"].may_read, false)
      denied = ask!(primary, params, context, scope(blocked, "alex"))

      assert_record!(first, north_record)
      assert_record!(second, south_record)
      assert_record!(retained, north_record)
      %{decision: :forbidden, records: []} = denied.recall
      [%{role: :system}, %{role: :user}] = denied.model_input

      trace = %{
        north: first,
        south: second,
        pending: Map.take(pending, [:tenant, :actor_id]),
        commit: %{decision: :forbidden, key: pending.record.key, record_present: false},
        actor_tenant_mismatch: %{read: :forbidden, put: :forbidden},
        read_after_write_revocation: retained,
        read_after_read_revocation: denied
      }

      json = Jason.encode!(trace, pretty: true)
      IO.puts(json)
      false = String.contains?(json, ["Unapproved refund", "Removed obsolete draft"])
    after
      Supervisor.stop(instance)
    end
  end

  defp scope(actors, id) do
    actor = Map.fetch!(actors, id)
    %{ash: %{tenant: actor.tenant, actor: actor}}
  end

  defp seed!(binding, context, key, summary) do
    source = Signal.new!("examples.memory.ash.seed", %{key: key}, source: "/examples/memory/ash-store")
    record = %{key: key, value: %{summary: summary}, source_signal_id: source.id}
    {:ok, ^record} = AshStore.put(binding, :resolutions, record, context)
    record
  end

  defp ask!(server, params, context, scope) do
    :ok = AgentServer.await_ready(server)
    session = Session.new(id: "ash-example-#{Jido.Id.uuid7()}")
    context = context |> Map.merge(scope) |> Map.put(:jido_ai_session, session)
    request = AshMemoryAgent.request_signal!(params)

    {:ok, %{status: :committed, reply: %{data: %{status: :completed, memory_trace: trace, output: answer}}}} =
      AgentServer.call(server, request, context: context, timeout: 120_000)

    Map.put(trace, :answer, answer)
  end

  defp assert_record!(trace, record) do
    %{decision: :allowed, records: [^record]} = trace.recall
    true = String.contains?(trace.answer, record.key)
    true = String.contains?(String.downcase(trace.answer), String.downcase(record.value.summary))
  end
end

SupportDesk.AshStoreExample.run(System.argv())
