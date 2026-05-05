if Code.ensure_loaded?(Ecto.Repo) do
  defmodule JidoMemory.Test.LivePostgresRepo do
    @moduledoc false

    use Ecto.Repo,
      otp_app: :jido_memory,
      adapter: Ecto.Adapters.Postgres
  end
else
  defmodule JidoMemory.Test.LivePostgresRepo do
    @moduledoc false
  end
end

defmodule Jido.Memory.StorePostgresIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Jido.Memory.Query
  alias Jido.Memory.Record
  alias Jido.Memory.Store.Postgres
  alias JidoMemory.Test.LivePostgresRepo

  @default_url "postgres://postgres:postgres@127.0.0.1:5432/jido_memory_test"

  setup_all do
    unless live_enabled?() do
      flunk("Set JIDO_MEMORY_POSTGRES_LIVE=1 to run live Postgres integration tests")
    end

    unless function_exported?(LivePostgresRepo, :start_link, 0) and
             Code.ensure_loaded?(Ecto.Adapters.SQL) and Code.ensure_loaded?(Postgrex) do
      flunk("Live Postgres tests require optional ecto_sql and postgrex dependencies")
    end

    Application.put_env(:jido_memory, LivePostgresRepo,
      url: System.get_env("JIDO_MEMORY_POSTGRES_URL", @default_url),
      pool_size: 1
    )

    {:ok, pid} = LivePostgresRepo.start_link()

    on_exit(fn ->
      stop_repo(pid)
    end)

    :ok
  end

  setup do
    table = "jido_memory_live_#{System.unique_integer([:positive, :monotonic])}"
    opts = [repo: LivePostgresRepo, table: table, ensure_table?: true]

    assert :ok = Postgres.ensure_ready(opts)

    on_exit(fn ->
      _ = apply(Ecto.Adapters.SQL, :query, [LivePostgresRepo, "DROP TABLE IF EXISTS \"#{table}\"", [], []])
    end)

    %{opts: opts, namespace: "agent:test-live-postgres"}
  end

  test "round-trips records and queries through a live postgres repo", %{opts: opts, namespace: namespace} do
    now = System.system_time(:millisecond)

    kept =
      Record.new!(%{
        id: "live-kept",
        namespace: namespace,
        class: :semantic,
        kind: :fact,
        text: "Postgres keeps binary payloads intact",
        content: %{nested: ["alpha", %{beta: 1}]},
        tags: ["postgres", "integration"],
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

    assert {:ok, %Record{id: "live-kept"}} = Postgres.put(kept, opts)
    assert {:ok, %Record{id: "live-skipped"}} = Postgres.put(skipped, opts)

    assert {:ok,
            %Record{
              id: "live-kept",
              content: %{nested: ["alpha", %{beta: 1}]},
              tags: ["postgres", "integration"]
            }} = Postgres.get({namespace, "live-kept"}, opts)

    query =
      Query.new!(%{
        namespace: namespace,
        classes: [:semantic],
        tags_all: ["postgres", "integration"],
        text_contains: "binary payloads",
        since: now - 5_000,
        until: now,
        order: :desc,
        limit: 5
      })

    assert {:ok, [%Record{id: "live-kept"}]} = Postgres.query(query, opts)
  end

  test "prune_expired removes expired rows", %{opts: opts, namespace: namespace} do
    now = System.system_time(:millisecond)

    expired =
      Record.new!(%{
        id: "expired",
        namespace: namespace,
        class: :working,
        kind: :signal_event,
        text: "prune me",
        expires_at: now - 10
      })

    active =
      Record.new!(%{
        id: "active",
        namespace: namespace,
        class: :working,
        kind: :signal_event,
        text: "keep me",
        expires_at: now + 60_000
      })

    assert {:ok, _record} = Postgres.put(expired, opts)
    assert {:ok, _record} = Postgres.put(active, opts)

    assert {:ok, 1} = Postgres.prune_expired(opts)
    assert :not_found = Postgres.get({namespace, "expired"}, opts)
    assert {:ok, %Record{id: "active"}} = Postgres.get({namespace, "active"}, opts)
  end

  defp live_enabled? do
    System.get_env("JIDO_MEMORY_POSTGRES_LIVE") in ["1", "true", "TRUE"]
  end

  defp stop_repo(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid)
  catch
    :exit, _reason -> :ok
  end
end
