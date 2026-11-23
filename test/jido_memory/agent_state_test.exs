defmodule Jido.Memory.AgentStateTest do
  use Jido.Memory.Testing.MemoryCase, fixture: Jido.Memory.Testing.AgentStateFixture, async: true

  alias Jido.Memory.Testing.AgentStateFixture

  @compile {:no_warn_undefined, AgentStateFixture}

  setup_all do
    assert Code.ensure_loaded?(Jido.Memory.Plugin), "implement the Jido v3 memory plugin to run the Agent fixture"
    Code.require_file("../support/fixtures/agent_state.exs", __DIR__)
    :ok
  end

  test "bounded collections evict the least recently written key", %{memory: memory} do
    value = %{issue: "duplicate_charge", summary: "Refund confirmed"}

    assert {:ok, memory, _} = AgentStateFixture.remember(memory, "T-17", value)
    assert {:ok, memory, _} = AgentStateFixture.remember(memory, "T-18", value)
    assert {:ok, memory, _} = AgentStateFixture.remember(memory, "T-19", value)
    assert {:ok, memory, _} = AgentStateFixture.remember(memory, "T-17", value)
    assert {:ok, memory, _} = AgentStateFixture.remember(memory, "T-20", value)

    assert {:ok, [%{key: "T-20"}, %{key: "T-17"}, %{key: "T-19"}]} =
             AgentStateFixture.recall(memory, limit: 3)
  end

  test "a rejected batch returns no Agent with partial writes", %{memory: memory} do
    value = %{issue: "duplicate_charge", summary: "Refund confirmed"}

    assert {:error, _} =
             AgentStateFixture.remember_batch(memory, [
               %{key: "T-17", value: value},
               %{key: "T-18", value: %{value | summary: 42}}
             ])

    assert {:ok, []} = AgentStateFixture.recall(memory, limit: 3)
  end

  test "recall from an Agent checks the collection name", %{memory: memory} do
    assert {:ok, []} = Jido.Memory.recall(memory, :resolutions)
    assert {:error, {:unknown_collection, :other}} = Jido.Memory.recall(memory, :other)
  end
end
