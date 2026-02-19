defmodule Jido.Memory.RuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Record
  alias Jido.Memory.Store.ETS

  setup do
    table = String.to_atom("jido_memory_facade_test_#{System.unique_integer([:positive])}")
    opts = [table: table]
    assert :ok = ETS.ensure_ready(opts)
    %{store: {ETS, opts}, opts: opts}
  end

  test "remember/get/forget with explicit namespace", %{store: store} do
    attrs = %{
      namespace: "agent:explicit",
      class: :semantic,
      kind: :fact,
      text: "Elixir runs on the BEAM",
      tags: ["elixir", "beam"]
    }

    assert {:ok, %Record{id: id}} = Jido.Memory.Runtime.remember(%{}, attrs, store: store)

    assert {:ok, %Record{id: ^id, namespace: "agent:explicit"}} =
             Jido.Memory.Runtime.get(%{}, id, namespace: "agent:explicit", store: store)

    assert {:ok, true} =
             Jido.Memory.Runtime.forget(%{}, id, namespace: "agent:explicit", store: store)

    assert {:error, :not_found} =
             Jido.Memory.Runtime.get(%{}, id, namespace: "agent:explicit", store: store)
  end

  test "namespace isolation defaults to per-agent ids when namespace is omitted", %{store: store} do
    assert {:ok, %Record{namespace: "agent:agent-a"}} =
             Jido.Memory.Runtime.remember(
               %{id: "agent-a"},
               %{class: :episodic, kind: :event, text: "A1"},
               store: store
             )

    assert {:ok, %Record{namespace: "agent:agent-b"}} =
             Jido.Memory.Runtime.remember(
               %{id: "agent-b"},
               %{class: :episodic, kind: :event, text: "B1"},
               store: store
             )

    assert {:ok, [%Record{text: "A1"}]} =
             Jido.Memory.Runtime.recall(%{id: "agent-a"}, %{store: store, order: :asc})

    assert {:ok, [%Record{text: "B1"}]} =
             Jido.Memory.Runtime.recall(%{id: "agent-b"}, %{store: store, order: :asc})
  end

  test "embedding metadata is stored and retrievable", %{store: store} do
    assert {:ok, %Record{id: id}} =
             Jido.Memory.Runtime.remember(
               %{},
               %{
                 namespace: "agent:embedding",
                 class: :semantic,
                 kind: :fact,
                 text: "vector ready",
                 embedding: [0.12, 0.98, 0.44],
                 metadata: %{provider: "none"}
               },
               store: store
             )

    assert {:ok, %Record{embedding: [0.12, 0.98, 0.44], metadata: %{provider: "none"}}} =
             Jido.Memory.Runtime.get(%{}, id, namespace: "agent:embedding", store: store)
  end
end
