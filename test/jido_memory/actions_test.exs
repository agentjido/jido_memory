defmodule Jido.Memory.ActionsTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Actions.{Forget, Recall, Remember, Retrieve}
  alias Jido.Memory.LongTermStore.ETS, as: LongTermETS
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.ProviderRef
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime
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

  test "retrieve action matches recall semantics", %{context: context} do
    assert {:ok, %{last_memory_id: _id}} =
             Remember.run(
               %{class: :episodic, kind: :event, text: "retrieve me", tags: ["x"]},
               context
             )

    assert {:ok, %{memory_results: [%Record{text: "retrieve me"}]}} =
             Retrieve.run(%{text_contains: "retrieve", order: :asc}, context)

    assert {:ok, %{memory_results: [%Record{text: "retrieve me"}]}} =
             Recall.run(%{text_contains: "retrieve", order: :asc}, context)
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

  test "actions keep working when the plugin state uses the Tiered provider" do
    unique = System.unique_integer([:positive])
    agent_id = "actions-tiered-#{unique}"

    provider =
      {Tiered,
       [
         short_store: {ETS, [table: :"jido_memory_actions_tiered_short_#{unique}"]},
         mid_store: {ETS, [table: :"jido_memory_actions_tiered_mid_#{unique}"]},
         long_term_store: {LongTermETS, [store: {ETS, [table: :"jido_memory_actions_tiered_long_#{unique}"]}]}
       ]}

    {:ok, provider_ref} = ProviderRef.normalize(provider)

    context = %{
      id: agent_id,
      state: %{
        __memory__: %{
          provider: provider_ref,
          auto_capture: true,
          capture_signal_patterns: []
        }
      }
    }

    assert {:ok, %{last_memory_id: id}} =
             Remember.run(
               %{class: :semantic, kind: :fact, text: "tiered action write", importance: 1.0},
               context
             )

    assert {:ok, %{memory_results: [%Record{id: ^id}]}} =
             Retrieve.run(%{text_contains: "tiered action write"}, context)

    assert {:ok, %{promoted_to_mid: 1}} =
             Runtime.consolidate(context, provider: provider, tier: :short)

    assert {:ok, %{last_memory_deleted?: true}} = Forget.run(%{id: id, tier: :mid}, context)
  end
end
