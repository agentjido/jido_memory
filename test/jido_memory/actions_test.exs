defmodule Jido.Memory.ActionsTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Actions.{Forget, Recall, Remember, Retrieve}
  alias Jido.Memory.{Record, RetrieveResult}
  alias Jido.Memory.Store.ETS

  setup do
    table = String.to_atom("jido_memory_actions_test_#{System.unique_integer([:positive])}")
    opts = [table: table]
    assert :ok = ETS.ensure_ready(opts)

    namespace = "agent:actions"

    context = %{
      state: %{
        __memory__: %{
          namespace: namespace,
          store: {ETS, opts},
          auto_capture: true,
          capture_signal_patterns: []
        }
      }
    }

    %{context: context, namespace: namespace, opts: opts}
  end

  test "remember action writes and returns last_memory_id", %{context: context} do
    params = %{class: :episodic, kind: :event, text: "action write", tags: ["test"]}

    assert {:ok, %{last_memory_id: id}} = Remember.run(params, context)
    assert is_binary(id)
  end

  test "recall action returns memory_results by default", %{context: context} do
    assert {:ok, %{last_memory_id: _id}} =
             Remember.run(
               %{class: :episodic, kind: :event, text: "recall me", tags: ["x"]},
               context
             )

    assert {:ok, %{memory_results: [%Record{text: "recall me"}]}} =
             Recall.run(%{text_contains: "recall", order: :asc}, context)
  end

  test "retrieve action returns canonical retrieve result", %{context: context} do
    assert {:ok, %{last_memory_id: _id}} =
             Remember.run(
               %{class: :episodic, kind: :event, text: "retrieve me", tags: ["x"]},
               context
             )

    assert {:ok, %{memory_result: %RetrieveResult{hits: [%{record: %Record{text: "retrieve me"}}]}}} =
             Retrieve.run(%{text_contains: "retrieve", order: :asc}, context)
  end

  test "forget action deletes and returns boolean", %{
    context: context,
    namespace: namespace,
    opts: opts
  } do
    assert {:ok, %{last_memory_id: id}} =
             Remember.run(%{class: :episodic, kind: :event, text: "delete me"}, context)

    assert {:ok, %{last_memory_deleted?: true}} = Forget.run(%{id: id}, context)
    assert :not_found = ETS.get({namespace, id}, opts)
  end

  test "actions support custom result keys and propagate runtime errors", %{context: context} do
    assert {:ok, %{saved_memory_id: id}} =
             Remember.run(
               %{
                 class: :episodic,
                 kind: :event,
                 text: "custom key",
                 memory_result_key: :saved_memory_id
               },
               context
             )

    assert {:ok, %{records_key: [%Record{id: ^id}]}} =
             Recall.run(%{text_contains: "custom", memory_result_key: :records_key}, context)

    assert {:ok, %{retrieve_key: %RetrieveResult{hits: [%{record: %Record{id: ^id}}]}}} =
             Retrieve.run(%{text_contains: "custom", memory_result_key: :retrieve_key}, context)

    assert {:error, {:invalid_class, "unknown"}} =
             Remember.run(%{class: "unknown", text: "bad class"}, context)

    assert {:error, {:invalid_order, :sideways}} = Recall.run(%{order: :sideways}, context)
    assert {:error, {:invalid_order, :sideways}} = Retrieve.run(%{order: :sideways}, context)
    assert {:error, :invalid_id} = Forget.run(%{id: nil}, context)
  end
end
