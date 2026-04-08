defmodule Jido.Memory.Explanation do
  @moduledoc """
  Canonical explainability payload for provider retrieval decisions.
  """

  alias Jido.Memory.{ProviderInfo, Query, Scope}

  @schema Zoi.struct(
            __MODULE__,
            %{
              query: Zoi.any(description: "Normalized retrieval query") |> Zoi.optional(),
              scope: Zoi.any(description: "Resolved retrieval scope") |> Zoi.optional(),
              provider: Zoi.any(description: "Provider metadata") |> Zoi.optional(),
              summary: Zoi.string(description: "Human-readable explanation summary") |> Zoi.optional(),
              reasons: Zoi.list(Zoi.any(), description: "Structured explanation reasons") |> Zoi.default([]),
              metadata: Zoi.map(description: "Stable explanation metadata") |> Zoi.default(%{}),
              extensions: Zoi.map(description: "Provider-native extras") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the explanation schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds and normalizes a retrieval explanation."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    with {:ok, query} <- normalize_query(get_attr(attrs, :query)),
         {:ok, scope} <- normalize_scope(get_attr(attrs, :scope)),
         {:ok, provider} <- normalize_provider(get_attr(attrs, :provider)),
         {:ok, summary} <- normalize_optional_string(get_attr(attrs, :summary), :invalid_summary),
         {:ok, reasons} <- normalize_reasons(get_attr(attrs, :reasons, [])),
         {:ok, metadata} <- normalize_map(get_attr(attrs, :metadata, %{}), :invalid_explanation_metadata),
         {:ok, extensions} <-
           normalize_map(get_attr(attrs, :extensions, %{}), :invalid_explanation_extensions) do
      {:ok,
       struct!(__MODULE__, %{
         query: query,
         scope: scope,
         provider: provider,
         summary: summary,
         reasons: reasons,
         metadata: metadata,
         extensions: extensions
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_explanation}

  @doc "Builds and normalizes an explanation, raising on error."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid explanation: #{inspect(reason)}"
    end
  end

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

  defp normalize_reasons(values) when is_list(values), do: {:ok, values}
  defp normalize_reasons(other), do: {:error, {:invalid_reasons, other}}

  defp normalize_optional_string(nil, _error), do: {:ok, nil}

  defp normalize_optional_string(value, _error) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: {:ok, nil}, else: {:ok, trimmed}
  end

  defp normalize_optional_string(other, error), do: {:error, {error, other}}

  defp normalize_map(%{} = map, _error), do: {:ok, map}
  defp normalize_map(nil, _error), do: {:ok, %{}}
  defp normalize_map(other, error), do: {:error, {error, other}}

  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
