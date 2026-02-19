defmodule Jido.Memory.ActionsTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Actions.{Forget, Recall, Remember}
  alias Jido.Memory.Record
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
end
