defmodule Jido.Memory.AshStoreTest do
  use ExUnit.Case, async: true

  alias Jido.Joi
  alias Jido.Memory.Store.Ash

  defmodule GeneratedAction do
    use Jido.Action, name: "test_generated_ash_action", schema: Joi.map()

    def __ash_jido__, do: %{}

    @impl true
    def run(params, %{ash: %{notify: pid, response: response} = scope}) do
      send(pid, {:ash_call, params, Map.take(scope, [:actor, :tenant])})
      response
    end
  end

  @binding %{
    put: GeneratedAction,
    get: GeneratedAction,
    query: GeneratedAction,
    delete: GeneratedAction,
    filter_fields: [:status]
  }
  @scope %{actor: "operator", tenant: "north"}
  @entry %{key: "T-17", value: %{status: "closed"}, source_signal_id: "ticket-closed"}

  test "requires generated Actions and a proper list of allowed fields" do
    assert :ok = Ash.validate_config(@binding)
    assert [:status] = Ash.filter_fields(@binding)
    assert {:error, :invalid_ash_filter_fields} = Ash.validate_config(%{@binding | filter_fields: ["status"]})
    assert {:error, :invalid_ash_actions} = Ash.validate_config(%{@binding | query: Jido.Memory.Actions.Access})
    assert {:error, :invalid_ash_actions} = Ash.validate_config(%{@binding | query: "invalid"})
    assert {:error, :invalid_ash_binding} = Ash.validate_config(Map.delete(@binding, :delete))
  end

  test "forwards only the scoped query and preserves the order of returned rows" do
    older = %{@entry | key: "T-16"}
    rows = [Map.put(@entry, :internal_id, 42), older]

    assert {:ok, [@entry, ^older]} =
             Ash.recall(@binding, :tickets, %{status: "closed"}, 2, context({:ok, %{result: rows}}))

    assert_received {:ash_call, %{collection: "tickets", where: %{status: "closed"}, limit: 2}, @scope}

    assert {:error, {:unsupported_store_filter, :private}} =
             Ash.recall(@binding, :tickets, %{private: true}, 1, context({:ok, %{result: []}}))

    refute_received {:ash_call, _, _}
  end

  test "rejects malformed Action responses and malformed rows" do
    for response <- [{:ok, %{}}, {:ok, %{result: @entry}}, {:ok, %{result: [@entry, %{key: "T-16"}]}}] do
      assert {:error, :invalid_ash_memory_result} = Ash.recall(@binding, :tickets, %{}, 2, context(response))
    end
  end

  test "forwards scoped host writes, reads, and deletes" do
    row = Map.put(@entry, :internal_id, 42)
    assert {:ok, @entry} = Ash.put(@binding, :tickets, @entry, context({:ok, %{result: row}}))
    assert_received {:ash_call, %{collection: "tickets", key: "T-17", value: %{status: "closed"}}, @scope}

    assert {:ok, @entry} = Ash.get(@binding, :tickets, "T-17", context({:ok, %{result: row}}))
    assert_received {:ash_call, %{collection: "tickets", key: "T-17"}, @scope}
    assert {:ok, nil} = Ash.get(@binding, :tickets, "T-16", context({:ok, %{result: nil}}))

    assert :ok = Ash.delete(@binding, :tickets, "T-17", context({:ok, %{result: row}}))
    assert_received {:ash_call, %{collection: "tickets", key: "T-17"}, @scope}
  end

  test "requires a live actor and tenant and maps the generated Action's access errors" do
    assert {:error, :forbidden} = Ash.get(@binding, :tickets, "T-17", %{ash: %{actor: @scope.actor, tenant: nil}})
    refute_received {:ash_call, _, _}

    not_found = context(action_error(:not_found))
    assert {:ok, nil} = Ash.get(@binding, :tickets, "T-17", not_found)
    assert :ok = Ash.delete(@binding, :tickets, "T-17", not_found)

    forbidden = context(action_error(:forbidden))
    assert {:error, :forbidden} = Ash.put(@binding, :tickets, @entry, forbidden)
    assert {:error, :forbidden} = Ash.get(@binding, :tickets, "T-17", forbidden)
    assert {:error, :forbidden} = Ash.recall(@binding, :tickets, %{}, 1, forbidden)
    assert {:error, :forbidden} = Ash.delete(@binding, :tickets, "T-17", forbidden)

    assert {:error, %{details: %{reason: :unknown}}} =
             Ash.get(@binding, :tickets, "T-17", context(action_error(:unknown)))
  end

  defp action_error(reason), do: {:error, Jido.Error.execution_error("Ash request failed", reason: reason)}
  defp context(response), do: %{ash: Map.merge(@scope, %{notify: self(), response: response}), unrelated: :ignored}
end
