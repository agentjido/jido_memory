defmodule Jido.Memory.StoreRedisIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Jido.Memory.Query
  alias Jido.Memory.Record
  alias Jido.Memory.Store.Redis
  alias JidoMemory.Test.LiveRedis

  setup_all do
    assert :ok = LiveRedis.ensure_ready()
    :ok
  end

  setup do
    prefix = LiveRedis.unique_prefix("jido:test:live-store")
    opts = [command_fn: LiveRedis.command_fn(), prefix: prefix]

    assert :ok = Redis.ensure_ready(opts)
    on_exit(fn -> :ok = LiveRedis.cleanup_prefix(prefix) end)

    %{opts: opts, namespace: "agent:test-live-store"}
  end

  test "round-trips records and queries through a live redis server", %{opts: opts, namespace: namespace} do
    now = System.system_time(:millisecond)

    kept =
      Record.new!(%{
        id: "live-kept",
        namespace: namespace,
        class: :semantic,
        kind: :fact,
        text: "Redis keeps binary payloads intact",
        content: %{nested: ["alpha", %{beta: 1}]},
        tags: ["redis", "integration"],
        observed_at: now - 2_000
      })

    skipped =
      Record.new!(%{
        id: "live-skipped",
        namespace: namespace,
        class: :episodic,
        kind: :event,
        text: "This should not match",
        tags: ["noise"],
        observed_at: now - 1_000
      })

    assert {:ok, %Record{id: "live-kept"}} = Redis.put(kept, opts)
    assert {:ok, %Record{id: "live-skipped"}} = Redis.put(skipped, opts)

    assert {:ok,
            %Record{
              id: "live-kept",
              content: %{nested: ["alpha", %{beta: 1}]},
              tags: ["redis", "integration"]
            }} = Redis.get({namespace, "live-kept"}, opts)

    query =
      Query.new!(%{
        namespace: namespace,
        classes: [:semantic],
        tags_all: ["redis", "integration"],
        text_contains: "binary payloads",
        since: now - 5_000,
        until: now,
        order: :desc,
        limit: 5
      })

    assert {:ok, [%Record{id: "live-kept"}]} = Redis.query(query, opts)
  end

  test "query drops orphaned indexes after redis ttl expiry", %{opts: opts, namespace: namespace} do
    ttl_opts = Keyword.put(opts, :ttl, 75)

    record =
      Record.new!(%{
        id: "ttl-query",
        namespace: namespace,
        class: :working,
        kind: :signal_event,
        text: "expires under redis ttl",
        tags: ["ttl", "query"]
      })

    assert {:ok, _record} = Redis.put(record, ttl_opts)

    Process.sleep(150)

    assert {:ok, []} =
             Redis.query(Query.new!(%{namespace: namespace, tags_any: ["ttl"]}), ttl_opts)

    assert {:ok, 0} = Redis.prune_expired(ttl_opts)
  end

  test "prune_expired removes ttl-expired records without a prior read", %{opts: opts, namespace: namespace} do
    ttl_opts = Keyword.put(opts, :ttl, 75)

    record =
      Record.new!(%{
        id: "ttl-prune",
        namespace: namespace,
        class: :working,
        kind: :signal_event,
        text: "prune me"
      })

    assert {:ok, _record} = Redis.put(record, ttl_opts)

    Process.sleep(150)

    assert {:ok, 1} = Redis.prune_expired(ttl_opts)
    assert :not_found = Redis.get({namespace, "ttl-prune"}, ttl_opts)
    assert {:ok, []} = Redis.query(Query.new!(%{namespace: namespace}), ttl_opts)
  end
end
