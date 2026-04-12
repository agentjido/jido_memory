defmodule Jido.Memory.StoreRedisTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Query
  alias Jido.Memory.Record
  alias Jido.Memory.Store.Redis
  alias JidoMemory.Test.MockRedis

  setup do
    {:ok, pid} = MockRedis.start_link()
    opts = [command_fn: MockRedis.command_fn(pid), prefix: "jido:test:#{System.unique_integer([:positive])}"]

    assert :ok = Redis.ensure_ready(opts)

    %{pid: pid, opts: opts, namespace: "agent:test-redis"}
  end

  test "put/get/delete lifecycle", %{opts: opts, namespace: namespace} do
    record =
      Record.new!(%{
        id: "redis-lifecycle",
        namespace: namespace,
        class: :semantic,
        kind: :fact,
        text: "The sky is blue",
        tags: ["weather"]
      })

    assert {:ok, %Record{id: "redis-lifecycle"}} = Redis.put(record, opts)
    assert {:ok, %Record{id: "redis-lifecycle"}} = Redis.get({namespace, "redis-lifecycle"}, opts)
    assert :ok = Redis.delete({namespace, "redis-lifecycle"}, opts)
    assert :not_found = Redis.get({namespace, "redis-lifecycle"}, opts)
  end

  test "overwriting a record refreshes its indexes", %{opts: opts, namespace: namespace} do
    first =
      Record.new!(%{
        id: "same-id",
        namespace: namespace,
        class: :episodic,
        kind: :event,
        text: "first",
        tags: ["old"],
        observed_at: System.system_time(:millisecond) - 1_000
      })

    second =
      Record.new!(%{
        id: "same-id",
        namespace: namespace,
        class: :semantic,
        kind: :fact,
        text: "second",
        tags: ["new"],
        observed_at: System.system_time(:millisecond)
      })

    assert {:ok, _} = Redis.put(first, opts)
    assert {:ok, _} = Redis.put(second, opts)

    assert {:ok, []} = Redis.query(Query.new!(%{namespace: namespace, tags_any: ["old"]}), opts)
    assert {:ok, [%Record{text: "second"}]} = Redis.query(Query.new!(%{namespace: namespace, tags_any: ["new"]}), opts)
  end

  test "query applies class tag time text filters and order limit", %{opts: opts, namespace: namespace} do
    now = System.system_time(:millisecond)

    records = [
      Record.new!(%{
        id: "r1",
        namespace: namespace,
        class: :episodic,
        kind: :user_query,
        text: "weather in seattle",
        tags: ["ai", "query"],
        observed_at: now - 3_000
      }),
      Record.new!(%{
        id: "r2",
        namespace: namespace,
        class: :episodic,
        kind: :assistant_response,
        text: "Seattle weather is rainy",
        tags: ["ai", "response"],
        observed_at: now - 2_000
      }),
      Record.new!(%{
        id: "r3",
        namespace: namespace,
        class: :working,
        kind: :signal_event,
        text: "bt.node.enter",
        tags: ["signal", "bt"],
        observed_at: now - 1_000
      })
    ]

    Enum.each(records, fn record ->
      assert {:ok, _} = Redis.put(record, opts)
    end)

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

    assert {:ok, [%Record{id: "r2"}]} = Redis.query(query, opts)

    assert {:ok, [%Record{id: "r3"}, %Record{id: "r2"}]} =
             Redis.query(Query.new!(%{namespace: namespace, order: :desc, limit: 2}), opts)
  end

  test "query excludes expired records", %{opts: opts, namespace: namespace} do
    past = System.system_time(:millisecond) - 10
    future = System.system_time(:millisecond) + 60_000

    expired =
      Record.new!(%{
        id: "expired",
        namespace: namespace,
        class: :episodic,
        kind: :event,
        text: "old",
        expires_at: past
      })

    active =
      Record.new!(%{
        id: "active",
        namespace: namespace,
        class: :episodic,
        kind: :event,
        text: "new",
        expires_at: future
      })

    assert {:ok, _} = Redis.put(expired, opts)
    assert {:ok, _} = Redis.put(active, opts)

    assert {:ok, [%Record{id: "active"}]} = Redis.query(Query.new!(%{namespace: namespace}), opts)
    assert :not_found = Redis.get({namespace, "expired"}, opts)
  end

  test "prune_expired removes records indexed by record expiry", %{opts: opts, namespace: namespace} do
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

    assert {:ok, _} = Redis.put(expired, opts)
    assert {:ok, _} = Redis.put(active, opts)

    assert {:ok, 1} = Redis.prune_expired(opts)
    assert :not_found = Redis.get({namespace, "expired"}, opts)
    assert {:ok, %Record{id: "active"}} = Redis.get({namespace, "active"}, opts)
  end

  test "prune_expired cleans records tracked only by store ttl", %{opts: opts, namespace: namespace} do
    ttl_opts = Keyword.put(opts, :ttl, 5)

    record =
      Record.new!(%{
        id: "ttl-only",
        namespace: namespace,
        class: :working,
        kind: :signal_event,
        text: "ttl"
      })

    assert {:ok, _} = Redis.put(record, ttl_opts)
    Process.sleep(10)

    assert {:ok, 1} = Redis.prune_expired(ttl_opts)
    assert :not_found = Redis.get({namespace, "ttl-only"}, ttl_opts)
    assert {:ok, []} = Redis.query(Query.new!(%{namespace: namespace}), ttl_opts)
  end

  test "ensure_ready reports missing command_fn" do
    assert {:error, {:redis_not_ready, %ArgumentError{}}} = Redis.ensure_ready([])
  end
end
