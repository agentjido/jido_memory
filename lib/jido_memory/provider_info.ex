defmodule Jido.Memory.ProviderInfo do
  @moduledoc """
  Canonical provider metadata returned by runtime/provider info calls.
  """

  alias Jido.Memory.{Capabilities, CapabilitySet, ProviderRegistry, Scope}

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.string(description: "Provider short name"),
              key: Zoi.atom(description: "Canonical provider key") |> Zoi.optional(),
              provider: Zoi.atom(description: "Concrete provider module"),
              provider_style: Zoi.atom(description: "Provider family or style") |> Zoi.optional(),
              version: Zoi.string(description: "Provider version") |> Zoi.optional(),
              description: Zoi.string(description: "Provider summary") |> Zoi.optional(),
              capabilities:
                Zoi.list(Zoi.atom(), description: "Supported capability atoms")
                |> Zoi.default([]),
              capability_descriptor:
                Zoi.map(description: "Structured capability descriptor")
                |> Zoi.default(Capabilities.default()),
              scope: Zoi.any(description: "Resolved provider scope") |> Zoi.optional(),
              topology: Zoi.map(description: "Provider topology metadata") |> Zoi.default(%{}),
              advanced_operations:
                Zoi.map(description: "Provider-direct advanced operations")
                |> Zoi.default(%{}),
              surface_boundary:
                Zoi.map(description: "Common-vs-provider-direct surface guidance")
                |> Zoi.default(%{}),
              defaults: Zoi.map(description: "Resolved provider defaults") |> Zoi.default(%{}),
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
    key = get_attr(attrs, :key, get_attr(attrs, :provider_key))
    name = get_attr(attrs, :name, Scope.provider_name(provider))

    with {:ok, name} <- normalize_required_string(name, :invalid_provider_name),
         {:ok, provider} <- normalize_provider(provider),
         {:ok, key} <- normalize_key(key, provider),
         {:ok, provider_style} <- normalize_optional_atom(get_attr(attrs, :provider_style), :invalid_provider_style),
         {:ok, version} <- normalize_optional_string(get_attr(attrs, :version)),
         {:ok, description} <- normalize_optional_string(get_attr(attrs, :description)),
         {:ok, capability_set} <- normalize_capability_set(attrs, provider, key),
         {:ok, scope} <- normalize_scope(get_attr(attrs, :scope)),
         {:ok, topology} <- normalize_map(get_attr(attrs, :topology, %{}), :invalid_provider_topology),
         {:ok, advanced_operations} <-
           normalize_map(get_attr(attrs, :advanced_operations, %{}), :invalid_provider_operations),
         {:ok, surface_boundary} <-
           normalize_map(get_attr(attrs, :surface_boundary, %{}), :invalid_provider_surface_boundary),
         {:ok, defaults} <- normalize_map(get_attr(attrs, :defaults, %{}), :invalid_provider_defaults),
         {:ok, metadata} <- normalize_metadata(get_attr(attrs, :metadata, %{})) do
      {:ok,
       struct!(__MODULE__, %{
         name: name,
         key: key,
         provider: provider,
         provider_style: provider_style,
         version: version,
         description: description,
         capabilities: capability_set.capabilities,
         capability_descriptor: capability_set.descriptor,
         scope: scope,
         topology: topology,
         advanced_operations: advanced_operations,
         surface_boundary: surface_boundary,
         defaults: defaults,
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
      key: Keyword.get(opts, :key, capability_set.key),
      provider: provider,
      provider_style: Keyword.get(opts, :provider_style),
      version: Keyword.get(opts, :version),
      description: Keyword.get(opts, :description),
      capabilities: capability_set.capabilities,
      capability_descriptor: capability_set.descriptor,
      scope: Keyword.get(opts, :scope),
      topology: Keyword.get(opts, :topology, %{}),
      advanced_operations: Keyword.get(opts, :advanced_operations, %{}),
      surface_boundary: Keyword.get(opts, :surface_boundary, %{}),
      defaults: Keyword.get(opts, :defaults, %{}),
      metadata: Keyword.get(opts, :metadata, capability_set.metadata)
    })
  end

  defp normalize_provider(provider) when is_atom(provider), do: {:ok, provider}
  defp normalize_provider(other), do: {:error, {:invalid_provider, other}}

  defp normalize_key(nil, provider), do: {:ok, ProviderRegistry.key_for(provider)}
  defp normalize_key(key, _provider) when is_atom(key), do: {:ok, key}
  defp normalize_key(other, _provider), do: {:error, {:invalid_provider_key, other}}

  defp normalize_scope(nil), do: {:ok, nil}
  defp normalize_scope(%Scope{} = scope), do: {:ok, scope}
  defp normalize_scope(%{} = attrs), do: Scope.new(attrs)
  defp normalize_scope(other), do: {:error, {:invalid_scope, other}}

  defp normalize_capability_set(attrs, provider, key) do
    case get_attr(attrs, :capability_set) do
      %CapabilitySet{} = capability_set ->
        {:ok, capability_set}

      nil ->
        CapabilitySet.new(%{
          provider: provider,
          key: key,
          capabilities: get_attr(attrs, :capabilities, []),
          descriptor: get_attr(attrs, :capability_descriptor, get_attr(attrs, :descriptor)),
          metadata: %{}
        })

      %{} = capability_set_attrs ->
        capability_set_attrs
        |> Map.put_new(:provider, provider)
        |> Map.put_new(:key, key)
        |> CapabilitySet.new()
    end
  end

  defp normalize_metadata(%{} = metadata), do: {:ok, metadata}
  defp normalize_metadata(nil), do: {:ok, %{}}
  defp normalize_metadata(other), do: {:error, {:invalid_provider_metadata, other}}

  defp normalize_map(%{} = map, _error), do: {:ok, map}
  defp normalize_map(nil, _error), do: {:ok, %{}}
  defp normalize_map(other, error), do: {:error, {error, other}}

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

  defp normalize_optional_atom(nil, _error), do: {:ok, nil}
  defp normalize_optional_atom(value, _error) when is_atom(value), do: {:ok, value}
  defp normalize_optional_atom(other, error), do: {:error, {error, other}}

  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
