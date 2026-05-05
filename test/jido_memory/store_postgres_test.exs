defmodule Jido.Memory.StorePostgresTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Query
  alias Jido.Memory.Record
  alias Jido.Memory.Store.Postgres
  alias JidoMemory.Test.MockPostgres

  defmodule Repo, do: nil

  setup do
    {:ok, pid} = MockPostgres.start_link()

    opts = [
      repo: Repo,
      query_fn: MockPostgres.query_fn(pid),
      table: "jido_memory_postgres_test_#{System.unique_integer([:positive])}"
    ]

    assert :ok = Postgres.ensure_ready(opts)

    %{pid: pid, opts: opts, namespace: "agent:test-postgres"}
  end

  test "validates required options without hard Ecto dependency", %{opts: opts} do
    assert :ok = Postgres.validate_options(opts)

    assert {:error, :missing_repo} =
             Postgres.validate_options(query_fn: opts[:query_fn])

    assert {:error, :invalid_repo} =
             Postgres.validate_options(repo: "Repo", query_fn: opts[:query_fn])

    assert {:error, :invalid_table} =
             Postgres.validate_options(repo: Repo, query_fn: opts[:query_fn], table: "bad-name")

    assert {:error, :invalid_prefix} =
             Postgres.validate_options(repo: Repo, query_fn: opts[:query_fn], prefix: "bad-name")

    assert {:error, :invalid_repo_opts} =
             Postgres.validate_options(repo: Repo, query_fn: opts[:query_fn], repo_opts: :bad)

    assert {:error, :invalid_ensure_table} =
             Postgres.validate_options(repo: Repo, query_fn: opts[:query_fn], ensure_table?: :bad)

    assert {:error, :invalid_query_fn} =
             Postgres.validate_options(repo: Repo, query_fn: fn _sql -> :ok end)

    assert {:error, :ecto_sql_not_available} =
             Postgres.validate_options(repo: Repo, sql_module: JidoMemory.Test.MissingPostgresSQL)
  end

  test "ensure_ready can create table and indexes for development and tests", %{pid: pid, opts: opts} do
    opts =
      opts
      |> Keyword.put(:table, :memory_table)
      |> Keyword.put(:prefix, :memory_schema)
      |> Keyword.put(:ensure_table?, true)

    assert :ok = Postgres.ensure_ready(opts)

    statements = Enum.map(MockPostgres.queries(pid), & &1.normalized)

    assert Enum.any?(
             statements,
             &String.starts_with?(&1, "CREATE TABLE IF NOT EXISTS \"memory_schema\".\"memory_table\"")
           )

    assert Enum.any?(statements, &String.contains?(&1, "\"memory_table_ns_observed_idx\""))
    assert Enum.any?(statements, &String.contains?(&1, "\"memory_table_ns_class_observed_idx\""))
    assert Enum.any?(statements, &String.contains?(&1, "\"memory_table_ns_kind_observed_idx\""))
    assert Enum.any?(statements, &String.contains?(&1, "\"memory_table_expires_idx\""))
  end

  test "reports a clean error when Ecto SQL is unavailable" do
    assert {:error, {:postgres_not_ready, :ecto_sql_not_available}} =
             Postgres.ensure_ready(repo: Repo, sql_module: JidoMemory.Test.MissingPostgresSQL)
  end

  test "put/get/delete lifecycle and binary record storage", %{pid: pid, opts: opts, namespace: namespace} do
    record =
      Record.new!(%{
        id: "pg-lifecycle",
        namespace: namespace,
        class: :semantic,
        kind: :fact,
        text: "The sky is blue",
        tags: ["weather"]
      })

    assert {:ok, %Record{id: "pg-lifecycle"}} = Postgres.put(record, opts)
    assert {:ok, %Record{id: "pg-lifecycle"}} = Postgres.get({namespace, "pg-lifecycle"}, opts)
    assert :ok = Postgres.delete({namespace, "pg-lifecycle"}, opts)
    assert :not_found = Postgres.get({namespace, "pg-lifecycle"}, opts)

    insert = Enum.find(MockPostgres.queries(pid), &String.starts_with?(&1.normalized, "INSERT INTO "))

    assert [^namespace, "pg-lifecycle", "semantic", "fact", "The sky is blue", nil, _observed_at, nil, binary] =
             insert.params

    assert {:ok, %Record{id: "pg-lifecycle", tags: ["weather"]}} = safe_binary_to_term(binary)
  end

  test "overwriting a record replaces queryable fields and payload", %{opts: opts, namespace: namespace} do
    first =
      Record.new!(%{
        id: "same-id",
        namespace: namespace,
        class: :episodic,
        kind: :event,
        text: "first",
        tags: ["old"]
      })

    second =
      Record.new!(%{
        id: "same-id",
        namespace: namespace,
        class: :semantic,
        kind: :fact,
        text: "second",
        tags: ["new"]
      })

    assert {:ok, _record} = Postgres.put(first, opts)
    assert {:ok, _record} = Postgres.put(second, opts)

    assert {:ok, []} = Postgres.query(Query.new!(%{namespace: namespace, tags_any: ["old"]}), opts)

    assert {:ok, [%Record{text: "second"}]} =
             Postgres.query(Query.new!(%{namespace: namespace, tags_any: ["new"]}), opts)
  end

  test "query applies SQL-backed and Elixir-backed filters", %{pid: pid, opts: opts, namespace: namespace} do
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
      assert {:ok, _record} = Postgres.put(record, opts)
    end)

    query =
      Query.new!(%{
        namespace: namespace,
        classes: [:episodic],
        kinds: [:assistant_response],
        tags_any: ["response"],
        text_contains: "seattle",
        since: now - 2_500,
        until: now,
        order: :desc,
        limit: 5
      })

    assert {:ok, [%Record{id: "r2"}]} = Postgres.query(query, opts)

    filtered_sql =
      pid
      |> select_record_queries()
      |> List.last()

    assert filtered_sql.normalized =~ "class = ANY"
    assert filtered_sql.normalized =~ "kind = ANY"
    assert filtered_sql.normalized =~ "observed_at >= "
    assert filtered_sql.normalized =~ "observed_at <= "
    refute Regex.match?(~r/ LIMIT \$\d+$/, filtered_sql.normalized)

    assert {:ok, [%Record{id: "r3"}, %Record{id: "r2"}]} =
             Postgres.query(Query.new!(%{namespace: namespace, order: :desc, limit: 2}), opts)

    limited_sql =
      pid
      |> select_record_queries()
      |> List.last()

    assert Regex.match?(~r/ LIMIT \$\d+$/, limited_sql.normalized)
    assert List.last(limited_sql.params) == 2
  end

  test "get and query exclude expired records and prune deletes them", %{opts: opts, namespace: namespace} do
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

    assert {:ok, _record} = Postgres.put(expired, opts)
    assert {:ok, _record} = Postgres.put(active, opts)

    assert :not_found = Postgres.get({namespace, "expired"}, opts)
    assert {:ok, [%Record{id: "active"}]} = Postgres.query(Query.new!(%{namespace: namespace}), opts)

    assert {:ok, 0} = Postgres.prune_expired(opts)

    second_expired = %{expired | id: "expired-again"}
    assert {:ok, _record} = Postgres.put(second_expired, opts)
    assert {:ok, 1} = Postgres.prune_expired(opts)
    assert :not_found = Postgres.get({namespace, "expired-again"}, opts)
  end

  test "operation errors are wrapped by callback", %{namespace: namespace} do
    opts = [repo: Repo, query_fn: fn _repo, _sql, _params, _repo_opts -> {:error, :boom} end]
    record = Record.new!(%{id: "boom", namespace: namespace, class: :semantic, kind: :fact})
    query = Query.new!(%{namespace: namespace})

    assert {:error, {:put_failed, :boom}} = Postgres.put(record, opts)
    assert {:error, {:get_failed, :boom}} = Postgres.get({namespace, "boom"}, opts)
    assert {:error, {:delete_failed, :boom}} = Postgres.delete({namespace, "boom"}, opts)
    assert {:error, {:query_failed, :boom}} = Postgres.query(query, opts)
    assert {:error, {:prune_failed, :boom}} = Postgres.prune_expired(opts)
  end

  defp select_record_queries(pid) do
    pid
    |> MockPostgres.queries()
    |> Enum.filter(&String.starts_with?(&1.normalized, "SELECT record FROM "))
    |> Enum.reject(&String.contains?(&1.normalized, " id = $2 "))
  end

  defp safe_binary_to_term(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> {:error, :invalid_term}
  end
end
