defmodule Jido.Memory.IngestRequest do
  @moduledoc """
  Canonical ingestion request for providers that support batch memory ingest.
  """

  alias Jido.Memory.{Record, Scope}

  @schema Zoi.struct(
            __MODULE__,
            %{
              records: Zoi.list(Zoi.any(), description: "Canonical records to ingest") |> Zoi.default([]),
              scope: Zoi.any(description: "Resolved ingest scope") |> Zoi.optional(),
              metadata: Zoi.map(description: "Stable ingest metadata") |> Zoi.default(%{}),
              extensions: Zoi.map(description: "Provider-native ingest extras") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the ingest request schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds and normalizes an ingest request."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    with {:ok, scope} <- normalize_scope(get_attr(attrs, :scope)),
         {:ok, records} <- normalize_records(get_attr(attrs, :records, []), scope),
         {:ok, metadata} <- normalize_map(get_attr(attrs, :metadata, %{}), :invalid_ingest_metadata),
         {:ok, extensions} <-
           normalize_map(get_attr(attrs, :extensions, %{}), :invalid_ingest_extensions) do
      {:ok,
       struct!(__MODULE__, %{
         records: records,
         scope: scope,
         metadata: metadata,
         extensions: extensions
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_ingest_request}

  @doc "Builds and normalizes an ingest request, raising on error."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid ingest request: #{inspect(reason)}"
    end
  end

  defp normalize_records(values, scope) when is_list(values) do
    namespace = scope_namespace(scope)

    values
    |> Enum.reduce_while([], fn value, acc ->
      case value do
        %Record{} = record ->
          {:cont, [inject_namespace(record, namespace) | acc]}

        %{} = attrs ->
          case Record.new(inject_namespace(attrs, namespace)) do
            {:ok, record} -> {:cont, [record | acc]}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        other ->
          {:halt, {:error, {:invalid_ingest_record, other}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      normalized -> {:ok, Enum.reverse(normalized)}
    end
  end

  defp normalize_records(other, _scope), do: {:error, {:invalid_ingest_records, other}}

  defp normalize_scope(nil), do: {:ok, nil}
  defp normalize_scope(%Scope{} = scope), do: {:ok, scope}
  defp normalize_scope(%{} = attrs), do: Scope.new(attrs)
  defp normalize_scope(other), do: {:error, {:invalid_scope, other}}

  defp normalize_map(%{} = map, _error), do: {:ok, map}
  defp normalize_map(nil, _error), do: {:ok, %{}}
  defp normalize_map(other, error), do: {:error, {error, other}}

  defp scope_namespace(%Scope{namespace: namespace}) when is_binary(namespace), do: namespace
  defp scope_namespace(_scope), do: nil

  defp inject_namespace(%Record{namespace: nil} = record, namespace) when is_binary(namespace),
    do: %{record | namespace: namespace}

  defp inject_namespace(%Record{} = record, _namespace), do: record

  defp inject_namespace(%{} = attrs, namespace) when is_binary(namespace) do
    case get_attr(attrs, :namespace) do
      nil -> Map.put(attrs, :namespace, namespace)
      "" -> Map.put(attrs, :namespace, namespace)
      _ -> attrs
    end
  end

  defp inject_namespace(attrs, _namespace), do: attrs

  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
