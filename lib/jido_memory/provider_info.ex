defmodule Jido.Memory.ProviderInfo do
  @moduledoc """
  Canonical provider metadata returned by runtime/provider info calls.
  """

  alias Jido.Memory.CapabilitySet
  alias Jido.Memory.Scope

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.string(description: "Provider short name"),
              provider: Zoi.atom(description: "Concrete provider module"),
              version: Zoi.string(description: "Provider version") |> Zoi.optional(),
              description: Zoi.string(description: "Provider summary") |> Zoi.optional(),
              capabilities:
                Zoi.list(Zoi.atom(), description: "Supported capability atoms")
                |> Zoi.default([]),
              scope: Zoi.any(description: "Resolved provider scope") |> Zoi.optional(),
              metadata: Zoi.map(description: "Additional provider metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the provider info schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds and normalizes provider info."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    provider = get_attr(attrs, :provider)
    name = get_attr(attrs, :name, Scope.provider_name(provider))

    with {:ok, name} <- normalize_required_string(name, :invalid_provider_name),
         {:ok, provider} <- normalize_provider(provider),
         {:ok, version} <- normalize_optional_string(get_attr(attrs, :version)),
         {:ok, description} <- normalize_optional_string(get_attr(attrs, :description)),
         {:ok, capabilities} <- normalize_capabilities(get_attr(attrs, :capabilities, [])),
         {:ok, scope} <- normalize_scope(get_attr(attrs, :scope)),
         {:ok, metadata} <- normalize_metadata(get_attr(attrs, :metadata, %{})) do
      {:ok,
       struct!(__MODULE__, %{
         name: name,
         provider: provider,
         version: version,
         description: description,
         capabilities: capabilities,
         scope: scope,
         metadata: metadata
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_provider_info}

  @doc "Builds and normalizes provider info, raising on error."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, info} -> info
      {:error, reason} -> raise ArgumentError, "invalid provider info: #{inspect(reason)}"
    end
  end

  @doc "Builds provider info from a capability set."
  @spec from_capabilities(module() | atom(), CapabilitySet.t(), keyword()) :: t()
  def from_capabilities(provider, %CapabilitySet{} = capability_set, opts \\ []) when is_list(opts) do
    new!(%{
      name: Keyword.get(opts, :name, Scope.provider_name(provider)),
      provider: provider,
      version: Keyword.get(opts, :version),
      description: Keyword.get(opts, :description),
      capabilities: capability_set.capabilities,
      scope: Keyword.get(opts, :scope),
      metadata: Keyword.get(opts, :metadata, capability_set.metadata)
    })
  end

  defp normalize_provider(provider) when is_atom(provider), do: {:ok, provider}
  defp normalize_provider(other), do: {:error, {:invalid_provider, other}}

  defp normalize_scope(nil), do: {:ok, nil}
  defp normalize_scope(%Scope{} = scope), do: {:ok, scope}
  defp normalize_scope(%{} = attrs), do: Scope.new(attrs)
  defp normalize_scope(other), do: {:error, {:invalid_scope, other}}

  defp normalize_capabilities(values) do
    case CapabilitySet.new(%{capabilities: values}) do
      {:ok, %CapabilitySet{capabilities: capabilities}} -> {:ok, capabilities}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_metadata(%{} = metadata), do: {:ok, metadata}
  defp normalize_metadata(nil), do: {:ok, %{}}
  defp normalize_metadata(other), do: {:error, {:invalid_provider_metadata, other}}

  defp normalize_required_string(value, error) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: {:error, {error, value}}, else: {:ok, trimmed}
  end

  defp normalize_required_string(other, error), do: {:error, {error, other}}

  defp normalize_optional_string(nil), do: {:ok, nil}

  defp normalize_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: {:ok, nil}, else: {:ok, trimmed}
  end

  defp normalize_optional_string(other), do: {:error, {:invalid_provider_string, other}}

  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
