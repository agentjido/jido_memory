defmodule Jido.Memory.Store.ETS do
  @moduledoc """
  ETS-backed memory store.

  This adapter is fast and simple but ephemeral. Data is lost on VM restart.
  """

  @behaviour Jido.Memory.Store

  alias Jido.Memory.Query
  alias Jido.Memory.Record

  @default_table :jido_memory

  @impl true
  @spec ensure_ready(keyword()) :: :ok | {:error, term()}
  def ensure_ready(opts) do
    ensure_tables(opts)
    :ok
  rescue
    e -> {:error, {:ets_setup_failed, e}}
  end

  @impl true
  @spec put(Record.t(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def put(%Record{} = record, opts) do
    ensure_tables(opts)

    key = {record.namespace, record.id}

    case :ets.lookup(records_table(opts), key) do
      [{^key, existing}] -> deindex_record(existing, opts)
      [] -> :ok
    end

    :ets.insert(records_table(opts), {key, record})
    index_record(record, opts)

    {:ok, record}
  rescue
    e -> {:error, {:put_failed, e}}
  end

  @impl true
  @spec get({String.t(), String.t()}, keyword()) ::
          {:ok, Record.t()} | :not_found | {:error, term()}
  def get({namespace, id}, opts) when is_binary(namespace) and is_binary(id) do
    ensure_tables(opts)

    key = {namespace, id}

    case :ets.lookup(records_table(opts), key) do
      [{^key, %Record{} = record}] ->
        if expired?(record) do
          delete({namespace, id}, opts)
          :not_found
        else
          {:ok, record}
        end

      [] ->
        :not_found
    end
  rescue
    e -> {:error, {:get_failed, e}}
  end

  @impl true
  @spec delete({String.t(), String.t()}, keyword()) :: :ok | {:error, term()}
  def delete({namespace, id}, opts) when is_binary(namespace) and is_binary(id) do
    ensure_tables(opts)

    key = {namespace, id}

    case :ets.lookup(records_table(opts), key) do
      [{^key, %Record{} = record}] ->
        deindex_record(record, opts)
        :ets.delete(records_table(opts), key)
        :ok

      [] ->
        :ok
    end
  rescue
    e -> {:error, {:delete_failed, e}}
  end

  @impl true
  @spec query(Query.t(), keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def query(%Query{namespace: nil}, _opts), do: {:error, :namespace_required}

  def query(%Query{} = query, opts) do
    ensure_tables(opts)

    candidate_sources = build_candidate_sources(query, opts)

    initial_ids =
      candidate_sources
      |> pick_narrowest_ids()
      |> MapSet.to_list()

    kind_keys = Query.kind_keys(query)
    text_filter = Query.downcased_text_filter(query)

    results =
      initial_ids
      |> Enum.reduce([], fn id, acc ->
        case :ets.lookup(records_table(opts), {query.namespace, id}) do
          [{{_, _}, %Record{} = record}] ->
            if record_matches?(record, query, kind_keys, text_filter),
              do: [record | acc],
              else: acc

          [] ->
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
    ensure_tables(opts)
    now = System.system_time(:millisecond)

    count =
      :ets.tab2list(records_table(opts))
      |> Enum.reduce(0, fn
        {{namespace, id}, %Record{expires_at: expires_at}}, acc
        when is_integer(expires_at) and expires_at <= now ->
          :ok = delete({namespace, id}, opts)
          acc + 1

        _, acc ->
          acc
      end)

    {:ok, count}
  rescue
    e -> {:error, {:prune_failed, e}}
  end

  @spec build_candidate_sources(Query.t(), keyword()) :: [{atom(), MapSet.t(String.t())}]
  defp build_candidate_sources(%Query{} = query, opts) do
    base = {:namespace_time, ids_from_namespace_time(query.namespace, opts)}

    with_class =
      if query.classes == [] do
        []
      else
        [{:class, ids_from_classes(query.namespace, query.classes, opts)}]
      end

    with_tags_any =
      if query.tags_any == [] do
        []
      else
        [{:tags_any, ids_from_tags_any(query.namespace, query.tags_any, opts)}]
      end

    with_tags_all =
      if query.tags_all == [] do
        []
      else
        [{:tags_all, ids_from_tags_all(query.namespace, query.tags_all, opts)}]
      end

    [base] ++ with_class ++ with_tags_any ++ with_tags_all
  end

  @spec pick_narrowest_ids([{atom(), MapSet.t(String.t())}]) :: MapSet.t(String.t())
  defp pick_narrowest_ids(sources) do
    {_source, ids} =
      Enum.min_by(sources, fn {_name, set} ->
        MapSet.size(set)
      end)

    ids
  end

  @spec ids_from_namespace_time(String.t(), keyword()) :: MapSet.t(String.t())
  defp ids_from_namespace_time(namespace, opts) do
    :ets.match_object(ns_time_table(opts), {{namespace, :_, :_}, :_})
    |> Enum.reduce(MapSet.new(), fn
      {{^namespace, _observed_at, id}, _}, acc -> MapSet.put(acc, id)
      _, acc -> acc
    end)
  end

  @spec ids_from_classes(String.t(), [Record.class()], keyword()) :: MapSet.t(String.t())
  defp ids_from_classes(namespace, classes, opts) do
    Enum.reduce(classes, MapSet.new(), fn class, acc ->
      class_ids =
        :ets.match_object(ns_class_time_table(opts), {{namespace, class, :_, :_}, :_})
        |> Enum.reduce(MapSet.new(), fn
          {{^namespace, ^class, _observed_at, id}, _}, ids -> MapSet.put(ids, id)
          _, ids -> ids
        end)

      MapSet.union(acc, class_ids)
    end)
  end

  @spec ids_from_tags_any(String.t(), [String.t()], keyword()) :: MapSet.t(String.t())
  defp ids_from_tags_any(namespace, tags, opts) do
    Enum.reduce(tags, MapSet.new(), fn tag, acc ->
      tag_ids =
        :ets.lookup(ns_tag_table(opts), {namespace, tag})
        |> Enum.reduce(MapSet.new(), fn
          {{^namespace, ^tag}, id}, ids -> MapSet.put(ids, id)
          _, ids -> ids
        end)

      MapSet.union(acc, tag_ids)
    end)
  end

  @spec ids_from_tags_all(String.t(), [String.t()], keyword()) :: MapSet.t(String.t())
  defp ids_from_tags_all(_namespace, [], _opts), do: MapSet.new()

  defp ids_from_tags_all(namespace, [first | rest], opts) do
    initial =
      :ets.lookup(ns_tag_table(opts), {namespace, first})
      |> Enum.reduce(MapSet.new(), fn
        {{^namespace, ^first}, id}, ids -> MapSet.put(ids, id)
        _, ids -> ids
      end)

    Enum.reduce(rest, initial, fn tag, acc ->
      current =
        :ets.lookup(ns_tag_table(opts), {namespace, tag})
        |> Enum.reduce(MapSet.new(), fn
          {{^namespace, ^tag}, id}, ids -> MapSet.put(ids, id)
          _, ids -> ids
        end)

      MapSet.intersection(acc, current)
    end)
  end

  @spec record_matches?(Record.t(), Query.t(), [String.t()], String.t() | nil) :: boolean()
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

  @spec class_matches?(Record.t(), [Record.class()]) :: boolean()
  defp class_matches?(_record, []), do: true
  defp class_matches?(%Record{class: class}, classes), do: class in classes

  @spec kind_matches?(Record.t(), [String.t()]) :: boolean()
  defp kind_matches?(_record, []), do: true

  defp kind_matches?(%Record{kind: kind}, kind_keys),
    do: Record.kind_key(kind) in kind_keys

  @spec tags_any_match?(Record.t(), [String.t()]) :: boolean()
  defp tags_any_match?(_record, []), do: true

  defp tags_any_match?(%Record{tags: tags}, tags_any),
    do: Enum.any?(tags_any, &(&1 in tags))

  @spec tags_all_match?(Record.t(), [String.t()]) :: boolean()
  defp tags_all_match?(_record, []), do: true

  defp tags_all_match?(%Record{tags: tags}, tags_all),
    do: Enum.all?(tags_all, &(&1 in tags))

  @spec time_matches?(Record.t(), integer() | nil, integer() | nil) :: boolean()
  defp time_matches?(%Record{observed_at: observed_at}, since, until) do
    lower_ok = if is_integer(since), do: observed_at >= since, else: true
    upper_ok = if is_integer(until), do: observed_at <= until, else: true
    lower_ok and upper_ok
  end

  @spec text_matches?(Record.t(), String.t() | nil) :: boolean()
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

  @spec sort_records([Record.t()], Query.order()) :: [Record.t()]
  defp sort_records(records, :asc) do
    Enum.sort_by(records, fn record -> {record.observed_at, record.id} end, :asc)
  end

  defp sort_records(records, :desc) do
    Enum.sort_by(records, fn record -> {record.observed_at, record.id} end, :desc)
  end

  @spec expired?(Record.t()) :: boolean()
  defp expired?(%Record{expires_at: nil}), do: false

  defp expired?(%Record{expires_at: expires_at}) when is_integer(expires_at),
    do: expires_at <= System.system_time(:millisecond)

  @spec index_record(Record.t(), keyword()) :: :ok
  defp index_record(%Record{} = record, opts) do
    :ets.insert(ns_time_table(opts), {{record.namespace, record.observed_at, record.id}, true})

    :ets.insert(
      ns_class_time_table(opts),
      {{record.namespace, record.class, record.observed_at, record.id}, true}
    )

    Enum.each(record.tags, fn tag ->
      :ets.insert(ns_tag_table(opts), {{record.namespace, tag}, record.id})
    end)

    :ok
  end

  @spec deindex_record(Record.t(), keyword()) :: :ok
  defp deindex_record(%Record{} = record, opts) do
    :ets.delete(ns_time_table(opts), {record.namespace, record.observed_at, record.id})

    :ets.delete(
      ns_class_time_table(opts),
      {record.namespace, record.class, record.observed_at, record.id}
    )

    Enum.each(record.tags, fn tag ->
      :ets.delete_object(ns_tag_table(opts), {{record.namespace, tag}, record.id})
    end)

    :ok
  end

  @spec ensure_tables(keyword()) :: :ok
  defp ensure_tables(opts) do
    ensure_table(records_table(opts), [:set])
    ensure_table(ns_time_table(opts), [:ordered_set])
    ensure_table(ns_class_time_table(opts), [:ordered_set])
    ensure_table(ns_tag_table(opts), [:bag])
  end

  @spec ensure_table(atom(), [atom()]) :: :ok
  defp ensure_table(name, type_opts) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(
          name,
          [:named_table, :public, read_concurrency: true, write_concurrency: true] ++ type_opts
        )

      _ ->
        :ok
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec records_table(keyword()) :: atom()
  defp records_table(opts), do: table_name(opts, :records)

  @spec ns_time_table(keyword()) :: atom()
  defp ns_time_table(opts), do: table_name(opts, :ns_time)

  @spec ns_class_time_table(keyword()) :: atom()
  defp ns_class_time_table(opts), do: table_name(opts, :ns_class_time)

  @spec ns_tag_table(keyword()) :: atom()
  defp ns_tag_table(opts), do: table_name(opts, :ns_tag)

  @spec table_name(keyword(), atom()) :: atom()
  defp table_name(opts, suffix) do
    base = Keyword.get(opts, :table, @default_table)

    base_atom =
      case base do
        atom when is_atom(atom) -> atom
        bin when is_binary(bin) -> String.to_atom(bin)
      end

    String.to_atom("#{base_atom}_#{suffix}")
  end
end
