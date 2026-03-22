defmodule Jido.Memory.RecordQuery do
  @moduledoc """
  Shared in-memory query evaluation for canonical memory records.

  This keeps backend-specific adapters aligned on the overlapping
  `Jido.Memory.Query` semantics when they need to evaluate structured filters on
  already-loaded records.
  """

  alias Jido.Memory.Query
  alias Jido.Memory.Record

  @spec filter(Enumerable.t(), Query.t() | map() | keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def filter(records, query)

  def filter(records, query) when is_list(query), do: filter(records, Map.new(query))

  def filter(records, %Query{} = query) do
    if is_binary(query.namespace) do
      kind_keys = Query.kind_keys(query)
      text_filter = Query.downcased_text_filter(query)

      results =
        records
        |> Enum.to_list()
        |> Enum.filter(&record_matches?(&1, query, kind_keys, text_filter))
        |> sort_records(query.order)
        |> Enum.take(query.limit)

      {:ok, results}
    else
      {:error, :namespace_required}
    end
  end

  def filter(records, query_attrs) when is_map(query_attrs) do
    with {:ok, query} <- Query.new(query_attrs) do
      filter(records, query)
    end
  end

  def filter(_records, _query), do: {:error, :invalid_query}

  @spec matches?(Record.t(), Query.t()) :: boolean()
  def matches?(%Record{} = record, %Query{} = query) do
    kind_keys = Query.kind_keys(query)
    text_filter = Query.downcased_text_filter(query)
    record_matches?(record, query, kind_keys, text_filter)
  end

  @spec expired?(Record.t()) :: boolean()
  def expired?(%Record{expires_at: nil}), do: false

  def expired?(%Record{expires_at: expires_at}) when is_integer(expires_at) do
    expires_at <= System.system_time(:millisecond)
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
  defp tags_any_match?(%Record{tags: tags}, tags_any), do: Enum.any?(tags_any, &(&1 in tags))

  defp tags_all_match?(_record, []), do: true
  defp tags_all_match?(%Record{tags: tags}, tags_all), do: Enum.all?(tags_all, &(&1 in tags))

  defp time_matches?(%Record{observed_at: observed_at}, since, until) do
    lower_ok = if is_integer(since), do: observed_at >= since, else: true
    upper_ok = if is_integer(until), do: observed_at <= until, else: true
    lower_ok and upper_ok
  end

  defp text_matches?(_record, nil), do: true

  defp text_matches?(%Record{text: text, content: content}, filter) do
    haystack = if is_binary(text) and text != "", do: text, else: inspect(content)

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
end
