defmodule Jido.Memory.ExternalStoreTest do
  use ExUnit.Case, async: true

  alias Jido.{AgentServer, Joi, Memory}
  alias Jido.Memory.Plugin
  alias Jido.Memory.Store.ETS

  @binding %{name: __MODULE__.Owner, scope: "support"}
  @record %{key: "T-17", value: %{summary: "Refunded"}, source_signal_id: "resolved-17"}

  defmodule ExternalAgent do
    use Jido.Agent, name: "external_memory_test", plugins: [Plugin]

    memory do
      external_collection :resolutions, store: {ETS, %{name: Jido.Memory.ExternalStoreTest.Owner, scope: "support"}} do
        schema(Joi.object(%{summary: Joi.string()}))
      end
    end

    routes do
      signal_source("/tests/memory/external")

      route "test.external.read", as: :read do
        action %{}, schema: Joi.object(%{}), context: context do
          with {:ok, records} <- Memory.recall(context, :resolutions), do: {:ok, %{records: records}}
        end

        state(:unchanged)
        reply("test.external.records", from: output())
      end

      route "test.external.write", as: :write do
        action %{}, schema: Joi.object(%{}), context: context do
          {:ok, context.agent_state, [Memory.remember(:resolutions, "T-18", %{summary: "New"})]}
        end
      end
    end
  end

  test "an external collection is read-only and returns only canonical record fields" do
    start_supervised!({ETS, name: @binding.name})
    start_supervised!({Jido, name: __MODULE__.Runtime})

    agent = ExternalAgent.instantiate!(id: "support")
    assert agent.state.memory == %{}
    assert {:error, :live_memory_required} = Memory.recall(agent, :resolutions)

    assert {:ok, server} = Jido.start_agent(__MODULE__.Runtime, agent)
    assert :ok = AgentServer.await_ready(server)
    assert :ok = ETS.put(@binding.name, @binding.scope, :resolutions, Map.put(@record, :metadata, "internal"))

    assert {:ok, %{reply: %{data: %{records: [@record]}}}} =
             AgentServer.call(server, ExternalAgent.read_signal!(%{}))

    assert {:ok, %{status: :failed, error: error}} =
             AgentServer.call(server, ExternalAgent.write_signal!(%{}))

    assert inspect(error) =~ "external_memory_write_requires_host"

    assert {:ok, %{reply: %{data: %{records: [@record]}}}} =
             AgentServer.call(server, ExternalAgent.read_signal!(%{}))
  end

  test "external collections reject an Agent-state retention limit" do
    collection = %{schema: Joi.object(%{summary: Joi.string()}), max_entries: 2, store: {ETS, @binding}}
    assert {:error, _} = Plugin.normalize(%{collections: %{resolutions: collection}})
  end

  test "ETS matches the exact collection, including names that resemble match patterns" do
    start_supervised!({ETS, name: @binding.name})
    other = %{key: "T-18", value: %{summary: "Other"}, source_signal_id: "resolved-18"}
    assert :ok = ETS.put(@binding.name, @binding.scope, :resolutions, @record)
    assert :ok = ETS.put(@binding.name, "other_scope", :_, other)

    for name <- [:_, :"$1"] do
      assert :ok = ETS.put(@binding.name, @binding.scope, name, other)
      assert {:ok, [^other]} = ETS.recall(@binding, name, %{}, 10, %{})
    end
  end

  test "ETS rejects malformed records before a write can affect recall" do
    start_supervised!({ETS, name: @binding.name})
    assert :ok = ETS.put(@binding.name, @binding.scope, :resolutions, @record)

    for key <- ["", String.duplicate("a", 257), <<255>>] do
      assert {:error, :invalid_key} = ETS.put(@binding.name, @binding.scope, :resolutions, %{@record | key: key})
    end

    assert {:error, :invalid_record} = ETS.put(@binding.name, @binding.scope, :resolutions, %{key: "incomplete"})
    assert {:ok, [@record]} = ETS.recall(@binding, :resolutions, %{}, 10, %{})
  end

  test "ETS filters before the limit, replaces old values, and deletes by scoped key" do
    start_supervised!({ETS, name: @binding.name})
    newer = %{@record | key: "T-18", value: %{summary: "Denied"}}
    updated = %{@record | value: %{summary: "Refunded", approved: true}}

    assert :ok = ETS.put(@binding.name, @binding.scope, :resolutions, @record)
    assert :ok = ETS.put(@binding.name, @binding.scope, :resolutions, newer)
    assert {:ok, [@record]} = ETS.recall(@binding, :resolutions, %{summary: "Refunded"}, 1, %{})

    assert :ok = ETS.put(@binding.name, @binding.scope, :resolutions, updated)
    assert :ok = ETS.put(@binding.name, "other_scope", :resolutions, @record)
    assert {:ok, [^updated, ^newer]} = ETS.recall(@binding, :resolutions, %{}, 10, %{})
    assert :ok = ETS.delete(@binding.name, @binding.scope, :resolutions, updated.key)
    assert {:ok, [^newer]} = ETS.recall(@binding, :resolutions, %{}, 10, %{})
    assert {:ok, [@record]} = ETS.recall(%{@binding | scope: "other_scope"}, :resolutions, %{}, 10, %{})
  end

  test "ETS distinguishes a stopped owner from an invalid binding" do
    assert {:error, :invalid_ets_binding} = ETS.validate_config(%{@binding | scope: ""})
    assert {:error, :store_unavailable} = ETS.recall(@binding, :resolutions, %{}, 1, %{})
  end

  test "a timed-out write can still apply and has a different result from a read timeout" do
    owner = start_supervised!({ETS, name: @binding.name})
    assert :ok = :sys.suspend(owner)

    try do
      write = Task.async(fn -> ETS.put(@binding.name, @binding.scope, :resolutions, @record) end)
      read = Task.async(fn -> ETS.recall(@binding, :resolutions, %{}, 1, %{}) end)

      assert {:error, :write_outcome_unknown} = Task.await(write, 7_000)
      assert {:error, :store_timeout} = Task.await(read, 7_000)
    after
      assert :ok = :sys.resume(owner)
    end

    assert {:ok, [@record]} = ETS.recall(@binding, :resolutions, %{}, 1, %{})
  end
end
