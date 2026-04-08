defmodule Jido.Memory.ConsolidationResult do
  @moduledoc """
  Canonical lifecycle/consolidation result for providers.
  """

  alias Jido.Memory.{ProviderInfo, Scope}

  @schema Zoi.struct(
            __MODULE__,
            %{
              scope: Zoi.any(description: "Resolved lifecycle scope") |> Zoi.optional(),
              provider: Zoi.any(description: "Provider metadata") |> Zoi.optional(),
              status: Zoi.atom(description: "Lifecycle operation status") |> Zoi.default(:ok),
              consolidated_count:
                Zoi.integer(description: "Records consolidated or rewritten")
                |> Zoi.default(0),
              pruned_count: Zoi.integer(description: "Records pruned as part of lifecycle") |> Zoi.default(0),
              metadata: Zoi.map(description: "Stable lifecycle metadata") |> Zoi.default(%{}),
              extensions: Zoi.map(description: "Provider-native lifecycle extras") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the consolidation result schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds and normalizes a consolidation result."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    with {:ok, scope} <- normalize_scope(get_attr(attrs, :scope)),
         {:ok, provider} <- normalize_provider(get_attr(attrs, :provider)),
         {:ok, status} <- normalize_status(get_attr(attrs, :status, :ok)),
         {:ok, consolidated_count} <-
           normalize_count(get_attr(attrs, :consolidated_count, 0), :invalid_consolidated_count),
         {:ok, pruned_count} <- normalize_count(get_attr(attrs, :pruned_count, 0), :invalid_pruned_count),
         {:ok, metadata} <- normalize_map(get_attr(attrs, :metadata, %{}), :invalid_consolidation_metadata),
         {:ok, extensions} <-
           normalize_map(get_attr(attrs, :extensions, %{}), :invalid_consolidation_extensions) do
      {:ok,
       struct!(__MODULE__, %{
         scope: scope,
         provider: provider,
         status: status,
         consolidated_count: consolidated_count,
         pruned_count: pruned_count,
         metadata: metadata,
         extensions: extensions
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_consolidation_result}

  @doc "Builds and normalizes a consolidation result, raising on error."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid consolidation result: #{inspect(reason)}"
    end
  end

  defp normalize_scope(nil), do: {:ok, nil}
  defp normalize_scope(%Scope{} = scope), do: {:ok, scope}
  defp normalize_scope(%{} = attrs), do: Scope.new(attrs)
  defp normalize_scope(other), do: {:error, {:invalid_scope, other}}

  defp normalize_provider(nil), do: {:ok, nil}
  defp normalize_provider(%ProviderInfo{} = info), do: {:ok, info}
  defp normalize_provider(%{} = attrs), do: ProviderInfo.new(attrs)
  defp normalize_provider(other), do: {:error, {:invalid_provider_info, other}}

  defp normalize_status(value) when is_atom(value), do: {:ok, value}
  defp normalize_status(other), do: {:error, {:invalid_consolidation_status, other}}

  defp normalize_count(value, _error) when is_integer(value) and value >= 0, do: {:ok, value}
  defp normalize_count(other, error), do: {:error, {error, other}}

  defp normalize_map(%{} = map, _error), do: {:ok, map}
  defp normalize_map(nil, _error), do: {:ok, %{}}
  defp normalize_map(other, error), do: {:error, {error, other}}

  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
