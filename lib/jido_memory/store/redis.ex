defmodule Jido.Memory.Store.Redis do
  @moduledoc """
  Redis-backed memory store.

  This adapter persists canonical `Jido.Memory.Record` structs in Redis without
  introducing a hard Redis client dependency into `jido_memory`.

  Callers provide a `:command_fn` option, typically a thin wrapper around a
  client such as Redix:

      fn args -> Redix.command(:memory_redis, args) end

  ## Options

  - `:command_fn` (required) - `fn([term()]) -> {:ok, term()} | {:error, term()}`
  - `:prefix` (optional, default `"jido:memory"`) - key namespace prefix
  - `:ttl` (optional) - Redis key TTL in milliseconds for stored record values

  ## Key Layout

      {prefix}:record:{namespace}:{id}        -> serialized `Record`
      {prefix}:meta:{namespace}:{id}          -> serialized index metadata
      {prefix}:z:ns:{namespace}:time          -> ZSET of ids by observed_at
      {prefix}:z:ns:{namespace}:class:{class} -> ZSET of ids by observed_at
      {prefix}:s:ns:{namespace}:tag:{tag}     -> SET of ids
      {prefix}:z:expires                      -> ZSET of namespace/id pairs by cleanup time

  The metadata key is intentionally left without a Redis TTL so expired record
  keys can still be deindexed when they are observed later by reads or pruning.
  """

  @behaviour Jido.Memory.Store

  alias Jido.Memory.{Query, Record}

  @default_prefix "jido:memory"
  @expiry_key_suffix "z:expires"

  @type index_metadata :: %{
          observed_at: integer(),
          class: term(),
          tags: [String.t()],
          cleanup_at: integer() | nil
        }

  @impl true
  @spec ensure_ready(keyword()) :: :ok | {:error, term()}
  def ensure_ready(opts) do
    command_fn = fetch_command_fn!(opts)

    case command_fn.(["PING"]) do
      {:ok, _pong} -> :ok
      {:error, reason} -> {:error, {:redis_not_ready, reason}}
    end
  rescue
    e -> {:error, {:redis_not_ready, e}}
  end

  @impl true
  @spec validate_options(keyword()) :: :ok | {:error, term()}
  def validate_options(opts) when is_list(opts) do
    _ = fetch_command_fn!(opts)
    _ = prefix(opts)
    _ = normalize_ttl(Keyword.get(opts, :ttl))
    :ok
  rescue
    error in ArgumentError ->
      message = Exception.message(error)

      cond do
        String.contains?(message, ":command_fn") -> {:error, :missing_command_fn}
        String.contains?(message, "invalid redis prefix") -> {:error, :invalid_prefix}
        String.contains?(message, "invalid redis ttl") -> {:error, :invalid_ttl}
        true -> {:error, {:invalid_redis_options, error}}
      end
  end

  def validate_options(_opts), do: {:error, :invalid_store_opts}

  @impl true
  @spec put(Record.t(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def put(%Record{} = record, opts) do
    command_fn = fetch_command_fn!(opts)
    validate_opts!(opts)

    metadata = build_index_metadata(record, opts)

    with :ok <- cleanup_existing_record(record.namespace, record.id, command_fn, opts),
         :ok <- persist_record(record, metadata, command_fn, opts),
         :ok <- index_record(record, metadata, command_fn, opts) do
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
    command_fn = fetch_command_fn!(opts)
    validate_opts!(opts)

    case fetch_record(namespace, id, command_fn, opts) do
      {:ok, %Record{} = record} ->
        if expired?(record) do
          :ok = delete({namespace, id}, opts)
          :not_found
        else
          {:ok, record}
        end

      :not_found ->
        :not_found

      {:error, _reason} = error ->
        error
    end
  rescue
    e -> {:error, {:get_failed, e}}
  end

  @impl true
  @spec delete({String.t(), String.t()}, keyword()) :: :ok | {:error, term()}
  def delete({namespace, id}, opts) when is_binary(namespace) and is_binary(id) do
    command_fn = fetch_command_fn!(opts)
    validate_opts!(opts)

    metadata = load_index_metadata(namespace, id, command_fn, opts)

    with :ok <- deindex_record(namespace, id, metadata, command_fn, opts),
         :ok <-
           run_commands(command_fn, [
             ["DEL", record_key(namespace, id, opts)],
             ["DEL", metadata_key(namespace, id, opts)],
             ["ZREM", expiry_key(opts), expiry_member(namespace, id)]
           ]) do
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
    command_fn = fetch_command_fn!(opts)
    validate_opts!(opts)

    kind_keys = Query.kind_keys(query)
    text_filter = Query.downcased_text_filter(query)

    results =
      query
      |> build_candidate_sources(command_fn, opts)
      |> pick_narrowest_ids()
      |> MapSet.to_list()
      |> Enum.reduce([], fn id, acc ->
        case fetch_record(query.namespace, id, command_fn, opts) do
          {:ok, %Record{} = record} ->
            if record_matches?(record, query, kind_keys, text_filter),
              do: [record | acc],
              else: acc

          :not_found ->
            acc

          {:error, _reason} ->
            acc
        end
      end)
      |> sort_records(query.order)
      |> Enum.take(query.limit)

    {:ok, results}
  rescue
    e -> {:error, {:query_failed, e}}
  end

  @impl true
  @spec prune_expired(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def prune_expired(opts) do
    command_fn = fetch_command_fn!(opts)
    validate_opts!(opts)
    now = System.system_time(:millisecond)

    count =
      command_fn
      |> expired_members(now, opts)
      |> Enum.reduce(0, fn member, acc ->
        case decode_expiry_member(member) do
          {:ok, {namespace, id}} ->
            case delete({namespace, id}, opts) do
              :ok -> acc + 1
              {:error, _reason} -> acc
            end

          {:error, _reason} ->
            acc
        end
      end)

    {:ok, count}
  rescue
    e -> {:error, {:prune_failed, e}}
  end

  defp cleanup_existing_record(namespace, id, command_fn, opts) do
    case load_index_metadata(namespace, id, command_fn, opts) do
      nil ->
        :ok

      metadata ->
        deindex_record(namespace, id, metadata, command_fn, opts)
    end
  end

  defp persist_record(%Record{} = record, metadata, command_fn, opts) do
    commands = [
      build_record_set_command(record, opts),
      ["SET", metadata_key(record.namespace, record.id, opts), :erlang.term_to_binary(metadata)]
    ]

    run_commands(command_fn, commands)
  end

  defp index_record(%Record{} = record, metadata, command_fn, opts) do
    commands =
      [
        ["ZADD", namespace_time_key(record.namespace, opts), Integer.to_string(record.observed_at), record.id],
        [
          "ZADD",
          namespace_class_time_key(record.namespace, record.class, opts),
          Integer.to_string(record.observed_at),
          record.id
        ]
      ] ++
        Enum.map(record.tags, fn tag ->
          ["SADD", namespace_tag_key(record.namespace, tag, opts), record.id]
        end) ++ expiry_commands(record.namespace, record.id, metadata.cleanup_at, opts)

    run_commands(command_fn, commands)
  end

  defp deindex_record(_namespace, _id, nil, _command_fn, _opts), do: :ok

  defp deindex_record(namespace, id, metadata, command_fn, opts) do
    commands =
      [
        ["ZREM", namespace_time_key(namespace, opts), id],
        ["ZREM", namespace_class_time_key(namespace, metadata.class, opts), id]
      ] ++
        Enum.map(metadata.tags, fn tag ->
          ["SREM", namespace_tag_key(namespace, tag, opts), id]
        end) ++
        [["ZREM", expiry_key(opts), expiry_member(namespace, id)]]

    run_commands(command_fn, commands)
  end

  defp fetch_record(namespace, id, command_fn, opts) do
    case command_fn.(["GET", record_key(namespace, id, opts)]) do
      {:ok, nil} ->
        cleanup_orphan(namespace, id, command_fn, opts)
        :not_found

      {:ok, binary} when is_binary(binary) ->
        case safe_binary_to_term(binary) do
          {:ok, %Record{} = record} -> {:ok, record}
          {:ok, _other} -> {:error, :invalid_record}
          {:error, _reason} = error -> error
        end

      {:error, reason} ->
        {:error, {:get_failed, reason}}

      _other ->
        {:error, :invalid_record}
    end
  end

  defp cleanup_orphan(namespace, id, command_fn, opts) do
    metadata = load_index_metadata(namespace, id, command_fn, opts)
    _ = deindex_record(namespace, id, metadata, command_fn, opts)
    _ = run_commands(command_fn, [["DEL", metadata_key(namespace, id, opts)]])
    :ok
  end

  defp load_index_metadata(namespace, id, command_fn, opts) do
    case command_fn.(["GET", metadata_key(namespace, id, opts)]) do
      {:ok, nil} ->
        nil

      {:ok, binary} when is_binary(binary) ->
        case safe_binary_to_term(binary) do
          {:ok, %{} = metadata} -> normalize_index_metadata(metadata)
          _ -> nil
        end

      _other ->
        nil
    end
  end

  defp normalize_index_metadata(%{} = metadata) do
    %{
      observed_at: Map.get(metadata, :observed_at, 0),
      class: Map.get(metadata, :class),
      tags: Map.get(metadata, :tags, []),
      cleanup_at: Map.get(metadata, :cleanup_at)
    }
  end

  defp build_index_metadata(%Record{} = record, opts) do
    now = System.system_time(:millisecond)
    ttl = normalize_ttl(Keyword.get(opts, :ttl))

    cleanup_at =
      [record.expires_at, ttl && now + ttl]
      |> Enum.filter(&is_integer/1)
      |> case do
        [] -> nil
        values -> Enum.min(values)
      end

    %{
      observed_at: record.observed_at,
      class: record.class,
      tags: record.tags,
      cleanup_at: cleanup_at
    }
  end

  defp expiry_commands(namespace, id, nil, opts),
    do: [["ZREM", expiry_key(opts), expiry_member(namespace, id)]]

  defp expiry_commands(namespace, id, cleanup_at, opts) when is_integer(cleanup_at) do
    [["ZADD", expiry_key(opts), Integer.to_string(cleanup_at), expiry_member(namespace, id)]]
  end

  defp build_candidate_sources(%Query{} = query, command_fn, opts) do
    base = {:namespace_time, ids_from_namespace_time(query, command_fn, opts)}

    with_class =
      if query.classes == [] do
        []
      else
        [{:class, ids_from_classes(query, command_fn, opts)}]
      end

    with_tags_any =
      if query.tags_any == [] do
        []
      else
        [{:tags_any, ids_from_tags_any(query, command_fn, opts)}]
      end

    with_tags_all =
      if query.tags_all == [] do
        []
      else
        [{:tags_all, ids_from_tags_all(query, command_fn, opts)}]
      end

    [base] ++ with_class ++ with_tags_any ++ with_tags_all
  end

  defp ids_from_namespace_time(%Query{} = query, command_fn, opts) do
    namespace_time_key(query.namespace, opts)
    |> zrange_by_score(command_fn, query.since, query.until)
    |> MapSet.new()
  end

  defp ids_from_classes(%Query{} = query, command_fn, opts) do
    Enum.reduce(query.classes, MapSet.new(), fn class, acc ->
      class_ids =
        query.namespace
        |> namespace_class_time_key(class, opts)
        |> zrange_by_score(command_fn, query.since, query.until)
        |> MapSet.new()

      MapSet.union(acc, class_ids)
    end)
  end

  defp ids_from_tags_any(%Query{} = query, command_fn, opts) do
    Enum.reduce(query.tags_any, MapSet.new(), fn tag, acc ->
      tag_ids =
        query.namespace
        |> namespace_tag_key(tag, opts)
        |> smembers(command_fn)
        |> MapSet.new()

      MapSet.union(acc, tag_ids)
    end)
  end

  defp ids_from_tags_all(%Query{} = query, command_fn, opts) do
    case query.tags_all do
      [] ->
        MapSet.new()

      [first | rest] ->
        initial =
          query.namespace
          |> namespace_tag_key(first, opts)
          |> smembers(command_fn)
          |> MapSet.new()

        Enum.reduce(rest, initial, fn tag, acc ->
          current =
            query.namespace
            |> namespace_tag_key(tag, opts)
            |> smembers(command_fn)
            |> MapSet.new()

          MapSet.intersection(acc, current)
        end)
    end
  end

  defp pick_narrowest_ids(sources) do
    {_source, ids} =
      Enum.min_by(sources, fn {_name, set} ->
        MapSet.size(set)
      end)

    ids
  end

  defp zrange_by_score(key, command_fn, since, until) do
    min = if is_integer(since), do: Integer.to_string(since), else: "-inf"
    max = if is_integer(until), do: Integer.to_string(until), else: "+inf"

    case command_fn.(["ZRANGEBYSCORE", key, min, max]) do
      {:ok, values} when is_list(values) -> values
      {:ok, nil} -> []
      _other -> []
    end
  end

  defp smembers(key, command_fn) do
    case command_fn.(["SMEMBERS", key]) do
      {:ok, values} when is_list(values) -> values
      {:ok, nil} -> []
      _other -> []
    end
  end

  defp expired_members(command_fn, now, opts) do
    case command_fn.(["ZRANGEBYSCORE", expiry_key(opts), "-inf", Integer.to_string(now)]) do
      {:ok, values} when is_list(values) -> values
      {:ok, nil} -> []
      _other -> []
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

  defp kind_matches?(%Record{kind: kind}, kind_keys),
    do: Record.kind_key(kind) in kind_keys

  defp tags_any_match?(_record, []), do: true

  defp tags_any_match?(%Record{tags: tags}, tags_any),
    do: Enum.any?(tags_any, &(&1 in tags))

  defp tags_all_match?(_record, []), do: true

  defp tags_all_match?(%Record{tags: tags}, tags_all),
    do: Enum.all?(tags_all, &(&1 in tags))

  defp time_matches?(%Record{observed_at: observed_at}, since, until) do
    lower_ok = if is_integer(since), do: observed_at >= since, else: true
    upper_ok = if is_integer(until), do: observed_at <= until, else: true
    lower_ok and upper_ok
  end

  defp text_matches?(_record, nil), do: true

  defp text_matches?(%Record{text: text, content: content}, filter) do
    haystack =
      cond do
        is_binary(text) and text != "" -> text
        true -> inspect(content)
      end

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

  defp build_record_set_command(%Record{} = record, opts) do
    value = :erlang.term_to_binary(record)

    case normalize_ttl(Keyword.get(opts, :ttl)) do
      nil ->
        ["SET", record_key(record.namespace, record.id, opts), value]

      ttl ->
        ["SET", record_key(record.namespace, record.id, opts), value, "PX", Integer.to_string(ttl)]
    end
  end

  defp run_commands(command_fn, commands) do
    Enum.reduce_while(commands, :ok, fn command, :ok ->
      case command_fn.(command) do
        {:ok, _value} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
        other -> {:halt, {:error, {:unexpected_redis_reply, other}}}
      end
    end)
  end

  defp validate_opts!(opts) do
    _ = prefix(opts)
    _ = normalize_ttl(Keyword.get(opts, :ttl))
    :ok
  end

  defp fetch_command_fn!(opts) do
    case Keyword.fetch(opts, :command_fn) do
      {:ok, fun} when is_function(fun, 1) -> fun
      _ -> raise ArgumentError, "#{__MODULE__} requires a :command_fn option"
    end
  end

  defp prefix(opts) do
    case Keyword.get(opts, :prefix, @default_prefix) do
      value when is_binary(value) and value != "" -> value
      value -> raise ArgumentError, "invalid redis prefix: #{inspect(value)}"
    end
  end

  defp normalize_ttl(nil), do: nil
  defp normalize_ttl(ttl) when is_integer(ttl) and ttl > 0, do: ttl
  defp normalize_ttl(ttl), do: raise(ArgumentError, "invalid redis ttl: #{inspect(ttl)}")

  defp record_key(namespace, id, opts), do: "#{prefix(opts)}:record:#{namespace}:#{id}"
  defp metadata_key(namespace, id, opts), do: "#{prefix(opts)}:meta:#{namespace}:#{id}"
  defp namespace_time_key(namespace, opts), do: "#{prefix(opts)}:z:ns:#{namespace}:time"

  defp namespace_class_time_key(namespace, class, opts),
    do: "#{prefix(opts)}:z:ns:#{namespace}:class:#{class_key(class)}"

  defp class_key(class) when is_atom(class), do: Atom.to_string(class)
  defp class_key(class) when is_binary(class), do: class
  defp class_key(class), do: inspect(class)

  defp namespace_tag_key(namespace, tag, opts), do: "#{prefix(opts)}:s:ns:#{namespace}:tag:#{tag}"
  defp expiry_key(opts), do: "#{prefix(opts)}:#{@expiry_key_suffix}"
  defp expiry_member(namespace, id), do: :erlang.term_to_binary({namespace, id})

  defp decode_expiry_member(member) when is_binary(member) do
    case safe_binary_to_term(member) do
      {:ok, {namespace, id}} when is_binary(namespace) and is_binary(id) ->
        {:ok, {namespace, id}}

      _ ->
        {:error, :invalid_expiry_member}
    end
  end

  defp safe_binary_to_term(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> {:error, :invalid_term}
  end
end
