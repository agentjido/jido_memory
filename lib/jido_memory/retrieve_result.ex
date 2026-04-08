defmodule Jido.Memory.RetrieveResult do
  @moduledoc """
  Canonical retrieval result returned by `Jido.Memory.Runtime.retrieve/3`.
  """

  alias Jido.Memory.{Hit, ProviderInfo, Query, Record, Scope}

  @schema Zoi.struct(
            __MODULE__,
            %{
              hits: Zoi.list(Zoi.any(), description: "Canonical retrieval hits") |> Zoi.default([]),
              query: Zoi.any(description: "Normalized retrieval query") |> Zoi.optional(),
              scope: Zoi.any(description: "Resolved retrieval scope") |> Zoi.optional(),
              provider: Zoi.any(description: "Provider metadata") |> Zoi.optional(),
              total_count: Zoi.integer(description: "Total hits returned") |> Zoi.default(0),
              metadata: Zoi.map(description: "Stable result metadata") |> Zoi.default(%{}),
              extensions: Zoi.map(description: "Provider-native extras") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the retrieve result schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds and normalizes a retrieval result."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    raw_hits = get_attr(attrs, :hits, get_attr(attrs, :records, []))

    with {:ok, hits} <- normalize_hits(raw_hits),
         {:ok, query} <- normalize_query(get_attr(attrs, :query)),
         {:ok, scope} <- normalize_scope(get_attr(attrs, :scope)),
         {:ok, provider} <- normalize_provider(get_attr(attrs, :provider)),
         {:ok, total_count} <- normalize_total_count(get_attr(attrs, :total_count, length(hits))),
         {:ok, metadata} <- normalize_map(get_attr(attrs, :metadata, %{}), :invalid_result_metadata),
         {:ok, extensions} <-
           normalize_map(get_attr(attrs, :extensions, %{}), :invalid_result_extensions) do
      {:ok,
       struct!(__MODULE__, %{
         hits: hits,
         query: query,
         scope: scope,
         provider: provider,
         total_count: total_count,
         metadata: metadata,
         extensions: extensions
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_retrieve_result}

  @doc "Builds and normalizes a retrieval result, raising on error."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "invalid retrieve result: #{inspect(reason)}"
    end
  end

  @doc "Wraps bare records into a canonical retrieval result."
  @spec from_records([Record.t()], keyword()) :: t()
  def from_records(records, opts \\ []) when is_list(records) and is_list(opts) do
    hits =
      records
      |> Enum.with_index(1)
      |> Enum.map(fn {record, rank} -> Hit.from_record(record, rank: rank) end)

    new!(%{
      hits: hits,
      query: Keyword.get(opts, :query),
      scope: Keyword.get(opts, :scope),
      provider: Keyword.get(opts, :provider),
      total_count: Keyword.get(opts, :total_count, length(hits)),
      metadata: Keyword.get(opts, :metadata, %{}),
      extensions: Keyword.get(opts, :extensions, %{})
    })
  end

  @doc "Returns the underlying record list from a retrieval result."
  @spec records(t()) :: [Record.t()]
  def records(%__MODULE__{hits: hits}) do
    Enum.map(hits, & &1.record)
  end

  defp normalize_hits(values) when is_list(values) do
    values
    |> Enum.with_index(1)
    |> Enum.reduce_while([], fn {value, index}, acc ->
      hit_result =
        case value do
          %Hit{} = hit ->
            {:ok, hit}

          %Record{} = record ->
            {:ok, Hit.from_record(record, rank: index)}

          %{} = attrs ->
            case Hit.new(attrs) do
              {:ok, %Hit{rank: nil} = hit} -> {:ok, %{hit | rank: index}}
              {:ok, hit} -> {:ok, hit}
              {:error, reason} -> {:error, reason}
            end

          other ->
            {:error, {:invalid_hit, other}}
        end

      case hit_result do
        {:ok, hit} -> {:cont, [hit | acc]}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      normalized -> {:ok, Enum.reverse(normalized)}
    end
  end

  defp normalize_hits(other), do: {:error, {:invalid_hits, other}}

  defp normalize_query(nil), do: {:ok, nil}
  defp normalize_query(%Query{} = query), do: {:ok, query}
  defp normalize_query(%{} = attrs), do: Query.new(attrs)
  defp normalize_query(other), do: {:error, {:invalid_query, other}}

  defp normalize_scope(nil), do: {:ok, nil}
  defp normalize_scope(%Scope{} = scope), do: {:ok, scope}
  defp normalize_scope(%{} = attrs), do: Scope.new(attrs)
  defp normalize_scope(other), do: {:error, {:invalid_scope, other}}

  defp normalize_provider(nil), do: {:ok, nil}
  defp normalize_provider(%ProviderInfo{} = info), do: {:ok, info}
  defp normalize_provider(%{} = attrs), do: ProviderInfo.new(attrs)
  defp normalize_provider(other), do: {:error, {:invalid_provider_info, other}}

  defp normalize_total_count(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp normalize_total_count(other), do: {:error, {:invalid_total_count, other}}

  defp normalize_map(%{} = map, _error), do: {:ok, map}
  defp normalize_map(nil, _error), do: {:ok, %{}}
  defp normalize_map(other, error), do: {:error, {error, other}}

  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
