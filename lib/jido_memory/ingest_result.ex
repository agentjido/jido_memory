defmodule Jido.Memory.IngestResult do
  @moduledoc """
  Canonical result for provider ingestion operations.
  """

  alias Jido.Memory.{ProviderInfo, Record, Scope}

  @schema Zoi.struct(
            __MODULE__,
            %{
              accepted_count: Zoi.integer(description: "Records accepted by the provider") |> Zoi.default(0),
              rejected: Zoi.list(Zoi.any(), description: "Rejected records or reasons") |> Zoi.default([]),
              records: Zoi.list(Zoi.any(), description: "Stored canonical records") |> Zoi.default([]),
              scope: Zoi.any(description: "Resolved ingest scope") |> Zoi.optional(),
              provider: Zoi.any(description: "Provider metadata") |> Zoi.optional(),
              metadata: Zoi.map(description: "Stable ingest result metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the ingest result schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds and normalizes an ingest result."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    raw_records = get_attr(attrs, :records, [])
    default_count = if is_list(raw_records), do: length(raw_records), else: 0

    with {:ok, accepted_count} <-
           normalize_count(get_attr(attrs, :accepted_count, default_count)),
         {:ok, rejected} <- normalize_rejected(get_attr(attrs, :rejected, [])),
         {:ok, records} <- normalize_records(raw_records),
         {:ok, scope} <- normalize_scope(get_attr(attrs, :scope)),
         {:ok, provider} <- normalize_provider(get_attr(attrs, :provider)),
         {:ok, metadata} <- normalize_metadata(get_attr(attrs, :metadata, %{})) do
      {:ok,
       struct!(__MODULE__, %{
         accepted_count: accepted_count,
         rejected: rejected,
         records: records,
         scope: scope,
         provider: provider,
         metadata: metadata
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_ingest_result}

  @doc "Builds and normalizes an ingest result, raising on error."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid ingest result: #{inspect(reason)}"
    end
  end

  defp normalize_count(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp normalize_count(other), do: {:error, {:invalid_accepted_count, other}}

  defp normalize_rejected(values) when is_list(values), do: {:ok, values}
  defp normalize_rejected(other), do: {:error, {:invalid_rejected, other}}

  defp normalize_records(values) when is_list(values) do
    values
    |> Enum.reduce_while([], fn
      %Record{} = record, acc ->
        {:cont, [record | acc]}

      %{} = attrs, acc ->
        case Record.new(attrs) do
          {:ok, record} -> {:cont, [record | acc]}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      other, _acc ->
        {:halt, {:error, {:invalid_ingest_result_record, other}}}
    end)
    |> case do
      {:error, _} = error -> error
      normalized -> {:ok, Enum.reverse(normalized)}
    end
  end

  defp normalize_records(other), do: {:error, {:invalid_records, other}}

  defp normalize_scope(nil), do: {:ok, nil}
  defp normalize_scope(%Scope{} = scope), do: {:ok, scope}
  defp normalize_scope(%{} = attrs), do: Scope.new(attrs)
  defp normalize_scope(other), do: {:error, {:invalid_scope, other}}

  defp normalize_provider(nil), do: {:ok, nil}
  defp normalize_provider(%ProviderInfo{} = info), do: {:ok, info}
  defp normalize_provider(%{} = attrs), do: ProviderInfo.new(attrs)
  defp normalize_provider(other), do: {:error, {:invalid_provider_info, other}}

  defp normalize_metadata(%{} = metadata), do: {:ok, metadata}
  defp normalize_metadata(nil), do: {:ok, %{}}
  defp normalize_metadata(other), do: {:error, {:invalid_ingest_result_metadata, other}}

  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
