defmodule Jido.Memory.StoreETSTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Query
  alias Jido.Memory.Record
  alias Jido.Memory.Store.ETS

  setup do
    table = String.to_atom("jido_memory_store_test_#{System.unique_integer([:positive])}")
    opts = [table: table]
    assert :ok = ETS.ensure_ready(opts)
    %{opts: opts, namespace: "agent:test-store"}
  end

  test "put/get/delete lifecycle", %{opts: opts, namespace: namespace} do
    record =
      Record.new!(%{
        id: "r_put_get_delete",
        namespace: namespace,
        class: :semantic,
        kind: :fact,
        text: "The sky is blue",
        tags: ["weather"]
      })

    assert {:ok, %Record{id: "r_put_get_delete"}} = ETS.put(record, opts)
    assert {:ok, %Record{id: "r_put_get_delete"}} = ETS.get({namespace, "r_put_get_delete"}, opts)
    assert :ok = ETS.delete({namespace, "r_put_get_delete"}, opts)
    assert :not_found = ETS.get({namespace, "r_put_get_delete"}, opts)
  end

  test "query applies class/tag/time/text filters and order+limit", %{
    opts: opts,
    namespace: namespace
  } do
    now = System.system_time(:millisecond)

    r1 =
      Record.new!(%{
        id: "r1",
        namespace: namespace,
        class: :episodic,
        kind: :user_query,
        text: "weather in seattle",
        tags: ["ai", "query"],
        observed_at: now - 3_000
      })

    r2 =
      Record.new!(%{
        id: "r2",
        namespace: namespace,
        class: :episodic,
        kind: :assistant_response,
        text: "Seattle weather is rainy",
        tags: ["ai", "response"],
        observed_at: now - 2_000
      })

    r3 =
      Record.new!(%{
        id: "r3",
        namespace: namespace,
        class: :working,
        kind: :signal_event,
        text: "bt.node.enter",
        tags: ["signal", "bt"],
        observed_at: now - 1_000
      })

    assert {:ok, _} = ETS.put(r1, opts)
    assert {:ok, _} = ETS.put(r2, opts)
    assert {:ok, _} = ETS.put(r3, opts)

    query =
      Query.new!(%{
        namespace: namespace,
        classes: [:episodic],
        tags_any: ["response"],
        text_contains: "seattle",
        since: now - 2_500,
        until: now,
        order: :desc,
        limit: 5
      })

    assert {:ok, [%Record{id: "r2"}]} = ETS.query(query, opts)

    ordered_query = Query.new!(%{namespace: namespace, order: :desc, limit: 2})
    assert {:ok, [%Record{id: "r3"}, %Record{id: "r2"}]} = ETS.query(ordered_query, opts)
  end

  test "prune_expired removes expired records only", %{opts: opts, namespace: namespace} do
    now = System.system_time(:millisecond)

    expired =
      Record.new!(%{
        id: "expired",
        namespace: namespace,
        class: :working,
        kind: :signal_event,
        text: "expired",
        expires_at: now - 10
      })

    active =
      Record.new!(%{
        id: "active",
        namespace: namespace,
        class: :working,
        kind: :signal_event,
        text: "active",
        expires_at: now + 60_000
      })

    assert {:ok, _} = ETS.put(expired, opts)
    assert {:ok, _} = ETS.put(active, opts)

    assert {:ok, 1} = ETS.prune_expired(opts)
    assert :not_found = ETS.get({namespace, "expired"}, opts)
    assert {:ok, %Record{id: "active"}} = ETS.get({namespace, "active"}, opts)
  end
end
