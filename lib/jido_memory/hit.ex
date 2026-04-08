defmodule Jido.Memory.Hit do
  @moduledoc """
  Canonical retrieval hit returned by providers.
  """

  alias Jido.Memory.Record

  @schema Zoi.struct(
            __MODULE__,
            %{
              record: Zoi.any(description: "Canonical memory record"),
              score: Zoi.any(description: "Provider-native ranking score") |> Zoi.optional(),
              rank: Zoi.integer(description: "1-based hit rank") |> Zoi.optional(),
              matched_on:
                Zoi.list(Zoi.string(), description: "Normalized match reasons")
                |> Zoi.default([]),
              metadata: Zoi.map(description: "Stable hit metadata") |> Zoi.default(%{}),
              extensions: Zoi.map(description: "Provider-native extras") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the hit schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds and normalizes a retrieval hit."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    with {:ok, record} <- normalize_record(get_attr(attrs, :record, get_attr(attrs, :memory))),
         {:ok, score} <- normalize_score(get_attr(attrs, :score)),
         {:ok, rank} <- normalize_rank(get_attr(attrs, :rank)),
         {:ok, matched_on} <- normalize_matched_on(get_attr(attrs, :matched_on, [])),
         {:ok, metadata} <- normalize_map(get_attr(attrs, :metadata, %{}), :invalid_hit_metadata),
         {:ok, extensions} <- normalize_map(get_attr(attrs, :extensions, %{}), :invalid_hit_extensions) do
      {:ok,
       struct!(__MODULE__, %{
         record: record,
         score: score,
         rank: rank,
         matched_on: matched_on,
         metadata: metadata,
         extensions: extensions
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_hit}

  @doc "Builds and normalizes a hit, raising on error."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, hit} -> hit
      {:error, reason} -> raise ArgumentError, "invalid memory hit: #{inspect(reason)}"
    end
  end

  @doc "Wraps a bare record as a canonical hit."
  @spec from_record(Record.t(), keyword()) :: t()
  def from_record(%Record{} = record, opts \\ []) when is_list(opts) do
    new!(%{
      record: record,
      score: Keyword.get(opts, :score),
      rank: Keyword.get(opts, :rank),
      matched_on: Keyword.get(opts, :matched_on, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      extensions: Keyword.get(opts, :extensions, %{})
    })
  end

  defp normalize_record(%Record{} = record), do: {:ok, record}
  defp normalize_record(%{} = attrs), do: Record.new(attrs)
  defp normalize_record(other), do: {:error, {:invalid_hit_record, other}}

  defp normalize_score(nil), do: {:ok, nil}
  defp normalize_score(score) when is_integer(score) or is_float(score), do: {:ok, score}
  defp normalize_score(other), do: {:error, {:invalid_hit_score, other}}

  defp normalize_rank(nil), do: {:ok, nil}
  defp normalize_rank(rank) when is_integer(rank) and rank > 0, do: {:ok, rank}
  defp normalize_rank(other), do: {:error, {:invalid_hit_rank, other}}

  defp normalize_matched_on(values) when is_list(values) do
    values
    |> Enum.reduce_while([], fn value, acc ->
      case value do
        v when is_binary(v) ->
          trimmed = String.trim(v)

          if trimmed == "" do
            {:cont, acc}
          else
            {:cont, [trimmed | acc]}
          end

        other ->
          {:halt, {:error, {:invalid_match_reason, other}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      normalized -> {:ok, Enum.reverse(normalized)}
    end
  end

  defp normalize_matched_on(nil), do: {:ok, []}
  defp normalize_matched_on(other), do: {:error, {:invalid_matched_on, other}}

  defp normalize_map(%{} = map, _error), do: {:ok, map}
  defp normalize_map(nil, _error), do: {:ok, %{}}
  defp normalize_map(other, error), do: {:error, {error, other}}

  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
