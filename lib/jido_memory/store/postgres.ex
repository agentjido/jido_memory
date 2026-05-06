defmodule Jido.Memory.Store.Postgres do
  @moduledoc """
  Postgres-backed memory store.

  This adapter persists canonical `Jido.Memory.Record` structs in Postgres
  through a caller-owned Ecto repo. `jido_memory` keeps Ecto and Postgrex as
  optional dependencies, so callers must add and start their own repo.

  ## Options

  - `:repo` (required) - caller-owned Ecto repo module
  - `:table` (optional, default `"jido_memory_records"`) - table name
  - `:prefix` (optional) - Postgres schema name
  - `:repo_opts` (optional, default `[]`) - options passed to
    `Ecto.Adapters.SQL.query/4`
  - `:ensure_table?` (optional, default `false`) - create the table and indexes
    from `ensure_ready/1`, intended for development and integration tests

  Tests can provide `:query_fn` as a four-arity function with the same argument
  shape as `Ecto.Adapters.SQL.query/4`.

  The table stores a full binary `Record` payload in a `bytea` column and keeps
  only the basic query fields duplicated in columns for filtering.
  """

  @behaviour Jido.Memory.Store

  alias Jido.Memory.{Query, Record}

  @default_table "jido_memory_records"
  @identifier_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/

  @impl true
  @spec ensure_ready(keyword()) :: :ok | {:error, term()}
  def ensure_ready(opts) when is_list(opts) do
    with :ok <- validate_options(opts),
         :ok <- maybe_ensure_table(opts),
         {:ok, _result} <- run_query(opts, "SELECT 1 FROM #{qualified_table(opts)} LIMIT 0", []) do
      :ok
    else
      {:error, reason} -> {:error, {:postgres_not_ready, reason}}
    end
  rescue
    e -> {:error, {:postgres_not_ready, e}}
  end

  def ensure_ready(_opts), do: {:error, {:postgres_not_ready, :invalid_store_opts}}

  @impl true
  @spec validate_options(keyword()) :: :ok | {:error, term()}
  def validate_options(opts) when is_list(opts) do
    with :ok <- validate_keyword_opts(opts),
         :ok <- validate_repo(opts),
         :ok <- validate_identifier_option(opts, :table, @default_table, :invalid_table),
         :ok <- validate_prefix(opts),
         :ok <- validate_repo_opts(opts),
         :ok <- validate_ensure_table(opts),
         :ok <- validate_query_fn(opts),
         :ok <- validate_sql_module(opts) do
      validate_query_backend(opts)
    end
  end

  def validate_options(_opts), do: {:error, :invalid_store_opts}

  @impl true
  @spec put(Record.t(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def put(%Record{} = record, opts) do
    with :ok <- validate_options(opts),
         {:ok, _result} <- run_query(opts, upsert_sql(opts), record_params(record)) do
      {:ok, record}
    else
      {:error, reason} -> {:error, {:put_failed, reason}}
    end
  rescue
    e -> {:error, {:put_failed, e}}
  end

  @impl true
  @spec get({String.t(), String.t()}, keyword()) ::
          {:ok, Record.t()} | :not_found | {:error, term()}
  def get({namespace, id}, opts) when is_binary(namespace) and is_binary(id) do
    with :ok <- validate_options(opts),
         {:ok, result} <- run_query(opts, get_sql(opts), [namespace, id]) do
      case result.rows do
        [] ->
          :not_found

        [[binary] | _] when is_binary(binary) ->
          with {:ok, %Record{} = record} <- decode_record(binary) do
            if expired?(record) do
              case delete({namespace, id}, opts) do
                :ok -> :not_found
                {:error, reason} -> {:error, reason}
              end
            else
              {:ok, record}
            end
          end

        _other ->
          {:error, :invalid_record}
      end
    else
      {:error, reason} -> {:error, {:get_failed, reason}}
    end
  rescue
    e -> {:error, {:get_failed, e}}
  end

  @impl true
  @spec delete({String.t(), String.t()}, keyword()) :: :ok | {:error, term()}
  def delete({namespace, id}, opts) when is_binary(namespace) and is_binary(id) do
    with :ok <- validate_options(opts),
         {:ok, _result} <- run_query(opts, delete_sql(opts), [namespace, id]) do
      :ok
    else
      {:error, reason} -> {:error, {:delete_failed, reason}}
    end
  rescue
    e -> {:error, {:delete_failed, e}}
  end

  @impl true
  @spec query(Query.t(), keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def query(%Query{namespace: nil}, _opts), do: {:error, :namespace_required}

  def query(%Query{} = query, opts) do
    with :ok <- validate_options(opts),
         {sql, params} <- build_query_sql(query, opts),
         {:ok, result} <- run_query(opts, sql, params),
         {:ok, records} <- decode_rows(result.rows) do
      kind_keys = Query.kind_keys(query)
      text_filter = Query.downcased_text_filter(query)

      results =
        records
        |> Enum.filter(&record_matches?(&1, query, kind_keys, text_filter))
        |> sort_records(query.order)
        |> Enum.take(query.limit)

      {:ok, results}
    else
      {:error, reason} -> {:error, {:query_failed, reason}}
    end
  rescue
    e -> {:error, {:query_failed, e}}
  end

  @impl true
  @spec prune_expired(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def prune_expired(opts) do
    now = System.system_time(:millisecond)

    with :ok <- validate_options(opts),
         {:ok, result} <- run_query(opts, prune_sql(opts), [now]) do
      {:ok, result.num_rows}
    else
      {:error, reason} -> {:error, {:prune_failed, reason}}
    end
  rescue
    e -> {:error, {:prune_failed, e}}
  end

  defp maybe_ensure_table(opts) do
    if ensure_table?(opts) do
      opts
      |> ddl_statements()
      |> Enum.reduce_while(:ok, fn statement, :ok ->
        case run_query(opts, statement, []) do
          {:ok, _result} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    else
      :ok
    end
  end

  defp ddl_statements(opts) do
    table = qualified_table(opts)

    [
      """
      CREATE TABLE IF NOT EXISTS #{table} (
        namespace text NOT NULL,
        id text NOT NULL,
        class text NOT NULL,
        kind text NOT NULL,
        text text,
        source text,
        observed_at bigint NOT NULL,
        expires_at bigint,
        record bytea NOT NULL,
        PRIMARY KEY (namespace, id)
      )
      """,
      "CREATE INDEX IF NOT EXISTS #{qualified_index(opts, "ns_observed_idx")} ON #{table} (namespace, observed_at, id)",
      "CREATE INDEX IF NOT EXISTS #{qualified_index(opts, "ns_class_observed_idx")} ON #{table} (namespace, class, observed_at, id)",
      "CREATE INDEX IF NOT EXISTS #{qualified_index(opts, "ns_kind_observed_idx")} ON #{table} (namespace, kind, observed_at, id)",
      "CREATE INDEX IF NOT EXISTS #{qualified_index(opts, "expires_idx")} ON #{table} (expires_at) WHERE expires_at IS NOT NULL"
    ]
  end

  defp upsert_sql(opts) do
    table = qualified_table(opts)

    """
    INSERT INTO #{table}
      (namespace, id, class, kind, text, source, observed_at, expires_at, record)
    VALUES
      ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    ON CONFLICT (namespace, id) DO UPDATE SET
      class = EXCLUDED.class,
      kind = EXCLUDED.kind,
      text = EXCLUDED.text,
      source = EXCLUDED.source,
      observed_at = EXCLUDED.observed_at,
      expires_at = EXCLUDED.expires_at,
      record = EXCLUDED.record
    """
  end

  defp get_sql(opts) do
    "SELECT record FROM #{qualified_table(opts)} WHERE namespace = $1 AND id = $2 LIMIT 1"
  end

  defp delete_sql(opts) do
    "DELETE FROM #{qualified_table(opts)} WHERE namespace = $1 AND id = $2"
  end

  defp prune_sql(opts) do
    "DELETE FROM #{qualified_table(opts)} WHERE expires_at IS NOT NULL AND expires_at <= $1"
  end

  defp build_query_sql(%Query{} = query, opts) do
    now = System.system_time(:millisecond)

    {conditions, params} =
      {["namespace = $1", "(expires_at IS NULL OR expires_at > $2)"], [query.namespace, now]}
      |> add_array_condition("class", Enum.map(query.classes, &Atom.to_string/1))
      |> add_array_condition("kind", Query.kind_keys(query))
      |> add_time_condition("observed_at >= ", query.since)
      |> add_time_condition("observed_at <= ", query.until)

    order = if query.order == :asc, do: "ASC", else: "DESC"
    base_sql = "SELECT record FROM #{qualified_table(opts)} WHERE #{Enum.join(conditions, " AND ")}"
    ordered_sql = "#{base_sql} ORDER BY observed_at #{order}, id #{order}"

    if elixir_only_filters?(query) do
      {ordered_sql, params}
    else
      limit_placeholder = placeholder(params)
      {"#{ordered_sql} LIMIT #{limit_placeholder}", params ++ [query.limit]}
    end
  end

  defp add_array_condition({conditions, params}, _column, []), do: {conditions, params}

  defp add_array_condition({conditions, params}, column, values) do
    condition = "#{column} = ANY(#{placeholder(params)}::text[])"
    {conditions ++ [condition], params ++ [values]}
  end

  defp add_time_condition({conditions, params}, _condition, nil), do: {conditions, params}

  defp add_time_condition({conditions, params}, condition, timestamp) do
    {conditions ++ ["#{condition}#{placeholder(params)}"], params ++ [timestamp]}
  end

  defp placeholder(params), do: "$#{length(params) + 1}"

  defp elixir_only_filters?(%Query{} = query) do
    query.tags_any != [] or query.tags_all != [] or not is_nil(Query.downcased_text_filter(query))
  end

  defp record_params(%Record{} = record) do
    [
      record.namespace,
      record.id,
      Atom.to_string(record.class),
      Record.kind_key(record.kind),
      record.text,
      record.source,
      record.observed_at,
      record.expires_at,
      :erlang.term_to_binary(record)
    ]
  end

  defp decode_rows(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn
      [binary], {:ok, acc} when is_binary(binary) ->
        case decode_record(binary) do
          {:ok, record} -> {:cont, {:ok, [record | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      _row, _acc ->
        {:halt, {:error, :invalid_record}}
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      {:error, _reason} = error -> error
    end
  end

  defp decode_record(binary) do
    case safe_binary_to_term(binary) do
      {:ok, %Record{} = record} -> {:ok, record}
      {:ok, _other} -> {:error, :invalid_record}
      {:error, _reason} = error -> error
    end
  end

  defp record_matches?(%Record{} = record, %Query{} = query, kind_keys, text_filter) do
    not expired?(record) and
      record.namespace == query.namespace and
      class_matches?(record, query.classes) and
      kind_matches?(record, kind_keys) and
      tags_any_match?(record, query.tags_any) and
      tags_all_match?(record, query.tags_all) and
      time_matches?(record, query.since, query.until) and
      text_matches?(record, text_filter)
  end

  defp class_matches?(_record, []), do: true
  defp class_matches?(%Record{class: class}, classes), do: class in classes

  defp kind_matches?(_record, []), do: true
  defp kind_matches?(%Record{kind: kind}, kind_keys), do: Record.kind_key(kind) in kind_keys

  defp tags_any_match?(_record, []), do: true

  defp tags_any_match?(%Record{tags: tags}, wanted),
    do: Enum.any?(wanted, &(&1 in tags))

  defp tags_all_match?(_record, []), do: true

  defp tags_all_match?(%Record{tags: tags}, wanted),
    do: Enum.all?(wanted, &(&1 in tags))

  defp time_matches?(%Record{observed_at: observed_at}, since, until) do
    (is_nil(since) or observed_at >= since) and
      (is_nil(until) or observed_at <= until)
  end

  defp text_matches?(_record, nil), do: true

  defp text_matches?(%Record{text: text, content: content}, filter) do
    haystack =
      if is_binary(text) and text != "",
        do: text,
        else: inspect(content)

    haystack
    |> String.downcase()
    |> String.contains?(filter)
  end

  defp sort_records(records, :asc) do
    Enum.sort_by(records, fn record -> {record.observed_at, record.id} end, :asc)
  end

  defp sort_records(records, :desc) do
    Enum.sort_by(records, fn record -> {record.observed_at, record.id} end, :desc)
  end

  defp expired?(%Record{expires_at: nil}), do: false

  defp expired?(%Record{expires_at: expires_at}) when is_integer(expires_at),
    do: expires_at <= System.system_time(:millisecond)

  defp run_query(opts, sql, params) do
    repo = Keyword.fetch!(opts, :repo)
    repo_opts = Keyword.get(opts, :repo_opts, [])

    result =
      case Keyword.get(opts, :query_fn) do
        query_fn when is_function(query_fn, 4) ->
          query_fn.(repo, sql, params, repo_opts)

        nil ->
          sql_module = sql_module(opts)

          if Code.ensure_loaded?(sql_module) and function_exported?(sql_module, :query, 4) do
            sql_module.query(repo, sql, params, repo_opts)
          else
            {:error, :ecto_sql_not_available}
          end
      end

    normalize_query_reply(result)
  rescue
    e -> {:error, e}
  end

  defp normalize_query_reply({:ok, %{} = result}) do
    {:ok,
     %{
       rows: Map.get(result, :rows) || [],
       num_rows: Map.get(result, :num_rows) || 0
     }}
  end

  defp normalize_query_reply({:error, reason}), do: {:error, reason}
  defp normalize_query_reply(other), do: {:error, {:unexpected_postgres_reply, other}}

  defp validate_keyword_opts(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, :invalid_store_opts}
  end

  defp validate_repo(opts) do
    case Keyword.fetch(opts, :repo) do
      {:ok, repo} when is_atom(repo) and not is_nil(repo) -> :ok
      {:ok, _repo} -> {:error, :invalid_repo}
      :error -> {:error, :missing_repo}
    end
  end

  defp validate_identifier_option(opts, key, default, error) do
    case normalize_identifier(Keyword.get(opts, key, default)) do
      {:ok, _value} -> :ok
      {:error, _reason} -> {:error, error}
    end
  end

  defp validate_prefix(opts) do
    case Keyword.get(opts, :prefix) do
      nil ->
        :ok

      value ->
        case normalize_identifier(value) do
          {:ok, _prefix} -> :ok
          {:error, _reason} -> {:error, :invalid_prefix}
        end
    end
  end

  defp validate_repo_opts(opts) do
    repo_opts = Keyword.get(opts, :repo_opts, [])

    if Keyword.keyword?(repo_opts), do: :ok, else: {:error, :invalid_repo_opts}
  end

  defp validate_ensure_table(opts) do
    case Keyword.get(opts, :ensure_table?, false) do
      value when is_boolean(value) -> :ok
      _value -> {:error, :invalid_ensure_table}
    end
  end

  defp validate_query_fn(opts) do
    case Keyword.get(opts, :query_fn) do
      nil -> :ok
      query_fn when is_function(query_fn, 4) -> :ok
      _query_fn -> {:error, :invalid_query_fn}
    end
  end

  defp validate_sql_module(opts) do
    case Keyword.get(opts, :sql_module, Ecto.Adapters.SQL) do
      module when is_atom(module) and not is_nil(module) -> :ok
      _module -> {:error, :invalid_sql_module}
    end
  end

  defp validate_query_backend(opts) do
    case Keyword.get(opts, :query_fn) do
      query_fn when is_function(query_fn, 4) ->
        :ok

      nil ->
        sql_module = sql_module(opts)

        if Code.ensure_loaded?(sql_module) and function_exported?(sql_module, :query, 4) do
          :ok
        else
          {:error, :ecto_sql_not_available}
        end
    end
  end

  defp sql_module(opts), do: Keyword.get(opts, :sql_module, Ecto.Adapters.SQL)

  defp ensure_table?(opts), do: Keyword.get(opts, :ensure_table?, false)

  defp qualified_table(opts) do
    quote_qualified_identifier(Keyword.get(opts, :prefix), Keyword.get(opts, :table, @default_table))
  end

  defp qualified_index(opts, suffix) do
    table = identifier_value!(Keyword.get(opts, :table, @default_table))
    index_name = index_name(table, suffix)

    quote_identifier(index_name)
  end

  defp quote_qualified_identifier(nil, name), do: quote_identifier(name)

  defp quote_qualified_identifier(prefix, name),
    do: "#{quote_identifier(prefix)}.#{quote_identifier(name)}"

  defp quote_identifier(value) do
    value
    |> identifier_value!()
    |> then(&~s("#{&1}"))
  end

  defp identifier_value!(value) do
    case normalize_identifier(value) do
      {:ok, normalized} -> normalized
      {:error, reason} -> raise ArgumentError, "invalid postgres identifier: #{inspect(reason)}"
    end
  end

  defp normalize_identifier(value) when is_atom(value) and not is_nil(value) do
    value
    |> Atom.to_string()
    |> normalize_identifier()
  end

  defp normalize_identifier(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> {:error, :empty}
      byte_size(trimmed) > 63 -> {:error, :too_long}
      Regex.match?(@identifier_pattern, trimmed) -> {:ok, trimmed}
      true -> {:error, :invalid_format}
    end
  end

  defp normalize_identifier(value), do: {:error, {:invalid_identifier, value}}

  defp index_name(table, suffix) do
    name = "#{table}_#{suffix}"

    if byte_size(name) <= 63 do
      name
    else
      table_prefix_length = max(1, 62 - byte_size(suffix))
      "#{String.slice(table, 0, table_prefix_length)}_#{suffix}"
    end
  end

  defp safe_binary_to_term(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> {:error, :invalid_term}
  end
end
