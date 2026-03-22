defmodule Jido.Memory.LongTermStore.Postgres do
  @moduledoc """
  Postgres-backed durable long-term store for the built-in Tiered provider.

  Postgres is the first supported durable backend because it gives the contract a
  practical production path with stronger persistence guarantees and richer
  indexing options than Redis while still fitting the current namespace-scoped
  long-term store seam.

  The initial implementation keeps the contract narrow on purpose:

  - direct SQL through `postgrex`
  - namespace and id pushed down to Postgres
  - overlapping structured query filters evaluated in Elixir through
    `Jido.Memory.RecordQuery`

  This keeps record preservation exact, preserves provider-managed metadata, and
  leaves room for backend-native query pushdown later without changing the
  public Tiered API.
  """

  @behaviour Jido.Memory.LongTermStore

  alias Jido.Memory.Query
  alias Jido.Memory.Record
  alias Jido.Memory.RecordQuery

  @default_schema "public"
  @default_table "jido_memory_long_term_records"

  @connection_keys [
    :hostname,
    :port,
    :username,
    :password,
    :database,
    :ssl,
    :ssl_opts,
    :socket_dir,
    :parameters,
    :timeout
  ]

  @impl true
  def validate_config(opts) when is_list(opts) do
    with :ok <- ensure_postgrex_available(),
         :ok <- validate_identifier(Keyword.get(opts, :schema, @default_schema)),
         :ok <- validate_identifier(Keyword.get(opts, :table, @default_table)) do
      case connection_opts(opts) do
        {:ok, _conn_opts} -> :ok
        {:error, _reason} = error -> error
      end
    end
  end

  def validate_config(_opts), do: {:error, :invalid_long_term_store_opts}

  @impl true
  def init(opts) do
    with :ok <- validate_config(opts),
         {:ok, _result} <- with_connection(opts, &ensure_schema!/2) do
      {:ok,
       %{
         backend: __MODULE__,
         adapter: :postgrex,
         schema: Keyword.get(opts, :schema, @default_schema),
         table: Keyword.get(opts, :table, @default_table),
         query_mode: :namespace_scan,
         selected_over: :redis
       }}
    end
  end

  @impl true
  def remember(target, attrs, opts) when is_list(attrs), do: remember(target, Map.new(attrs), opts)

  def remember(_target, attrs, opts) when is_map(attrs) and is_list(opts) do
    with :ok <- validate_config(opts),
         {:ok, namespace} <- runtime_namespace(opts),
         {:ok, record} <- build_record(attrs, namespace, opts),
         {:ok, _result} <-
           with_connection(opts, fn conn, ref ->
             Postgrex.query(conn, upsert_sql(ref), encode_record_params(record))
           end) do
      {:ok, record}
    end
  end

  def remember(_target, _attrs, _opts), do: {:error, :invalid_attrs}

  @impl true
  def get(_target, id, opts) when is_binary(id) and is_list(opts) do
    with :ok <- validate_config(opts),
         {:ok, namespace} <- runtime_namespace(opts),
         {:ok, %Postgrex.Result{rows: rows}} <-
           with_connection(opts, fn conn, ref ->
             Postgrex.query(conn, get_sql(ref), [namespace, id])
           end) do
      decode_get_result(rows, id, opts)
    end
  end

  def get(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def retrieve(target, query, opts) when is_list(query), do: retrieve(target, Map.new(query), opts)

  def retrieve(_target, %Query{} = query, opts) when is_list(opts) do
    with :ok <- validate_config(opts),
         {:ok, effective_query} <- attach_namespace(query, opts),
         {:ok, records} <- select_namespace_records(opts, effective_query.namespace) do
      RecordQuery.filter(records, effective_query)
    end
  end

  def retrieve(_target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with :ok <- validate_config(opts),
         {:ok, namespace} <- runtime_namespace(opts),
         {:ok, query} <- build_query(query_attrs, namespace),
         {:ok, records} <- select_namespace_records(opts, namespace) do
      RecordQuery.filter(records, query)
    end
  end

  def retrieve(_target, _query, _opts), do: {:error, :invalid_query}

  @impl true
  def forget(_target, id, opts) when is_binary(id) and is_list(opts) do
    with :ok <- validate_config(opts),
         {:ok, namespace} <- runtime_namespace(opts),
         {:ok, %Postgrex.Result{num_rows: num_rows}} <-
           with_connection(opts, fn conn, ref ->
             Postgrex.query(conn, forget_sql(ref), [namespace, id])
           end) do
      {:ok, num_rows > 0}
    end
  end

  def forget(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def prune(_target, opts) when is_list(opts) do
    with :ok <- validate_config(opts),
         {:ok, namespace} <- runtime_namespace(opts),
         now = System.system_time(:millisecond),
         {:ok, %Postgrex.Result{num_rows: num_rows}} <-
           with_connection(opts, fn conn, ref ->
             Postgrex.query(conn, prune_sql(ref), [namespace, now])
           end) do
      {:ok, num_rows}
    end
  end

  def prune(_target, _opts), do: {:error, :invalid_long_term_store_opts}

  @impl true
  def info(backend_meta, :all), do: {:ok, backend_meta}

  def info(backend_meta, fields) when is_list(fields) do
    {:ok, Map.take(backend_meta, fields)}
  end

  def info(_backend_meta, _fields), do: {:error, :invalid_info_fields}

  defp ensure_schema!(conn, ref) do
    with {:ok, _result} <- Postgrex.query(conn, create_table_sql(ref), []),
         {:ok, _result} <- Postgrex.query(conn, create_observed_index_sql(ref), []),
         {:ok, _result} <- Postgrex.query(conn, create_expires_index_sql(ref), []) do
      {:ok, :ready}
    end
  end

  defp select_namespace_records(opts, namespace) do
    now = System.system_time(:millisecond)

    with {:ok, %Postgrex.Result{rows: rows}} <-
           with_connection(opts, fn conn, ref ->
             Postgrex.query(conn, select_namespace_sql(ref), [namespace, now])
           end) do
      {:ok, Enum.flat_map(rows, &decode_row/1)}
    end
  end

  defp decode_get_result([], _id, _opts), do: {:error, :not_found}

  defp decode_get_result([[payload]], id, opts) do
    case decode_payload(payload) do
      {:ok, %Record{} = record} ->
        if RecordQuery.expired?(record) do
          _ = forget(%{}, id, opts)
          {:error, :not_found}
        else
          {:ok, record}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_row([payload]) do
    case decode_payload(payload) do
      {:ok, %Record{} = record} -> [record]
      {:error, _reason} -> []
    end
  end

  defp decode_row(_row), do: []

  defp decode_payload(payload) when is_binary(payload) do
    case :erlang.binary_to_term(payload, [:safe]) do
      %Record{} = record -> {:ok, record}
      map when is_map(map) -> Record.new(map)
      other -> {:error, {:invalid_long_term_payload, other}}
    end
  rescue
    error -> {:error, {:invalid_long_term_payload, error}}
  end

  defp encode_record_params(%Record{} = record) do
    [record.namespace, record.id, record.observed_at, record.expires_at, :erlang.term_to_binary(record)]
  end

  defp build_record(attrs, namespace, opts) when is_map(attrs) do
    now = Keyword.get(opts, :now, System.system_time(:millisecond))

    attrs
    |> Map.drop([:provider, "provider"])
    |> Map.put(:namespace, namespace)
    |> Map.put_new(:observed_at, now)
    |> Record.new(now: now)
  end

  defp build_query(attrs, namespace) do
    attrs
    |> Map.drop([:provider, "provider"])
    |> Map.put_new(:namespace, namespace)
    |> Query.new()
  end

  defp attach_namespace(%Query{namespace: nil} = query, opts) do
    with {:ok, namespace} <- runtime_namespace(opts) do
      {:ok, %{query | namespace: namespace}}
    end
  end

  defp attach_namespace(%Query{} = query, _opts), do: {:ok, query}

  defp runtime_namespace(opts) do
    case Keyword.get(opts, :namespace) do
      namespace when is_binary(namespace) ->
        namespace = String.trim(namespace)

        if namespace != "" do
          {:ok, namespace}
        else
          {:error, :namespace_required}
        end

      _other ->
        {:error, :namespace_required}
    end
  end

  defp with_connection(opts, callback) do
    with {:ok, conn_opts} <- connection_opts(opts),
         {:ok, ref} <- table_ref(opts),
         {:ok, pid} <- Postgrex.start_link(conn_opts) do
      try do
        callback.(pid, ref)
      after
        GenServer.stop(pid)
      end
    else
      {:error, _reason} = error -> error
    end
  end

  defp connection_opts(opts) do
    connect_opts = Keyword.get(opts, :connect_opts)

    cond do
      is_list(connect_opts) and connect_opts != [] ->
        {:ok, connect_opts}

      is_binary(Keyword.get(opts, :url)) ->
        {:ok, [url: Keyword.fetch!(opts, :url)]}

      is_binary(Keyword.get(opts, :database)) ->
        {:ok,
         opts
         |> Keyword.take(@connection_keys)
         |> Keyword.reject(fn {_key, value} -> is_nil(value) end)}

      true ->
        {:error, :database_required}
    end
  end

  defp table_ref(opts) do
    schema = Keyword.get(opts, :schema, @default_schema)
    table = Keyword.get(opts, :table, @default_table)

    with :ok <- validate_identifier(schema),
         :ok <- validate_identifier(table) do
      {:ok,
       %{
         schema: schema,
         table: table,
         quoted_table: quoted_identifier(schema, table),
         observed_index: quoted_single_identifier("#{table}_namespace_observed_at_idx"),
         expires_index: quoted_single_identifier("#{table}_namespace_expires_at_idx")
       }}
    end
  end

  defp validate_identifier(value) when is_binary(value) do
    if String.match?(value, ~r/^[A-Za-z_][A-Za-z0-9_]*$/) do
      :ok
    else
      {:error, {:invalid_identifier, value}}
    end
  end

  defp validate_identifier(_value), do: {:error, :invalid_identifier}

  defp quoted_identifier(schema, table), do: ~s("#{schema}"."#{table}")
  defp quoted_single_identifier(identifier), do: ~s("#{identifier}")

  defp create_table_sql(ref) do
    """
    CREATE TABLE IF NOT EXISTS #{ref.quoted_table} (
      namespace TEXT NOT NULL,
      id TEXT NOT NULL,
      observed_at BIGINT NOT NULL,
      expires_at BIGINT,
      payload BYTEA NOT NULL,
      inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (namespace, id)
    )
    """
  end

  defp create_observed_index_sql(ref) do
    """
    CREATE INDEX IF NOT EXISTS #{ref.observed_index}
    ON #{ref.quoted_table} (namespace, observed_at DESC)
    """
  end

  defp create_expires_index_sql(ref) do
    """
    CREATE INDEX IF NOT EXISTS #{ref.expires_index}
    ON #{ref.quoted_table} (namespace, expires_at)
    """
  end

  defp upsert_sql(ref) do
    """
    INSERT INTO #{ref.quoted_table} (namespace, id, observed_at, expires_at, payload)
    VALUES ($1, $2, $3, $4, $5)
    ON CONFLICT (namespace, id)
    DO UPDATE SET
      observed_at = EXCLUDED.observed_at,
      expires_at = EXCLUDED.expires_at,
      payload = EXCLUDED.payload,
      updated_at = NOW()
    """
  end

  defp get_sql(ref) do
    """
    SELECT payload
    FROM #{ref.quoted_table}
    WHERE namespace = $1 AND id = $2
    LIMIT 1
    """
  end

  defp select_namespace_sql(ref) do
    """
    SELECT payload
    FROM #{ref.quoted_table}
    WHERE namespace = $1
      AND (expires_at IS NULL OR expires_at > $2)
    """
  end

  defp forget_sql(ref) do
    """
    DELETE FROM #{ref.quoted_table}
    WHERE namespace = $1 AND id = $2
    """
  end

  defp prune_sql(ref) do
    """
    DELETE FROM #{ref.quoted_table}
    WHERE namespace = $1
      AND expires_at IS NOT NULL
      AND expires_at <= $2
    """
  end

  defp ensure_postgrex_available do
    case Code.ensure_loaded(Postgrex) do
      {:module, Postgrex} -> :ok
      {:error, _reason} -> {:error, :postgrex_not_available}
    end
  end
end
