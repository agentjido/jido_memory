defmodule Jido.Memory.CapabilitySet do
  @moduledoc """
  Normalized capability descriptor for a memory provider.
  """

  alias Jido.Memory.{Capabilities, ProviderRegistry}

  @schema Zoi.struct(
            __MODULE__,
            %{
              provider: Zoi.atom(description: "Concrete provider module or alias") |> Zoi.optional(),
              key: Zoi.atom(description: "Canonical provider key") |> Zoi.optional(),
              capabilities:
                Zoi.list(Zoi.atom(), description: "Supported capability atoms")
                |> Zoi.default([]),
              descriptor:
                Zoi.map(description: "Structured capability descriptor")
                |> Zoi.default(Capabilities.default()),
              metadata: Zoi.map(description: "Additional capability metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the capability set schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds and normalizes a capability set."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    provider = get_attr(attrs, :provider)
    key = get_attr(attrs, :key, get_attr(attrs, :provider_key))
    raw_capabilities = get_attr(attrs, :capabilities, [])
    raw_descriptor = get_attr(attrs, :descriptor, get_attr(attrs, :capability_descriptor))

    {capability_input, descriptor_input} =
      case {raw_capabilities, raw_descriptor} do
        {%{} = descriptor, nil} -> {[], descriptor}
        _ -> {raw_capabilities, raw_descriptor}
      end

    with {:ok, provider} <- normalize_provider(provider),
         {:ok, key} <- normalize_key(key, provider),
         {:ok, capabilities} <- normalize_capabilities_input(capability_input),
         {:ok, descriptor} <- normalize_descriptor_input(descriptor_input, capabilities),
         {:ok, capabilities} <- merge_capabilities(capabilities, descriptor),
         {:ok, metadata} <- normalize_metadata(get_attr(attrs, :metadata, %{})) do
      {:ok,
       struct!(__MODULE__, %{
         provider: provider,
         key: key,
         capabilities: capabilities,
         descriptor: descriptor,
         metadata: metadata
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_capability_set}

  @doc "Builds and normalizes a capability set, raising on error."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid capability set: #{inspect(reason)}"
    end
  end

  @doc "Returns true when the capability set includes the given capability."
  @spec supports?(t(), atom() | [atom()]) :: boolean()
  def supports?(%__MODULE__{capabilities: capabilities}, capability) when is_atom(capability) do
    capability in capabilities
  end

  def supports?(%__MODULE__{descriptor: descriptor}, capability_path) when is_list(capability_path) do
    Capabilities.supported?(descriptor, capability_path)
  end

  @doc "Returns a structured capability value by nested path."
  @spec get(t(), [atom()]) :: term()
  def get(%__MODULE__{descriptor: descriptor}, capability_path) when is_list(capability_path) do
    Capabilities.get(descriptor, capability_path)
  end

  defp normalize_provider(nil), do: {:ok, nil}
  defp normalize_provider(provider) when is_atom(provider), do: {:ok, provider}
  defp normalize_provider(other), do: {:error, {:invalid_provider, other}}

  defp normalize_key(nil, provider), do: {:ok, ProviderRegistry.key_for(provider)}
  defp normalize_key(key, _provider) when is_atom(key), do: {:ok, key}
  defp normalize_key(other, _provider), do: {:error, {:invalid_provider_key, other}}

  defp normalize_capabilities_input(values) when is_list(values) do
    values
    |> Enum.reduce_while([], fn
      value, acc when is_atom(value) ->
        if value in acc, do: {:cont, acc}, else: {:cont, [value | acc]}

      other, _acc ->
        {:halt, {:error, {:invalid_capability, other}}}
    end)
    |> case do
      {:error, _} = error -> error
      normalized -> {:ok, Enum.reverse(normalized)}
    end
  end

  defp normalize_capabilities_input(%{}), do: {:ok, []}
  defp normalize_capabilities_input(nil), do: {:ok, []}
  defp normalize_capabilities_input(other), do: {:error, {:invalid_capabilities, other}}

  defp normalize_descriptor_input(nil, capabilities) do
    {:ok, Capabilities.from_flat_list(capabilities)}
  end

  defp normalize_descriptor_input(%{} = descriptor, capabilities) do
    descriptor =
      case capabilities do
        [] -> descriptor
        _ -> Map.merge(Capabilities.from_flat_list(capabilities), descriptor)
      end

    {:ok, Capabilities.normalize(descriptor)}
  end

  defp normalize_descriptor_input(other, _capabilities), do: {:error, {:invalid_capability_descriptor, other}}

  defp merge_capabilities(capabilities, descriptor) when is_list(capabilities) and is_map(descriptor) do
    merged =
      case capabilities do
        [] -> Capabilities.flatten_supported(descriptor)
        values -> values
      end

    {:ok, Enum.uniq(merged)}
  end

  defp normalize_metadata(%{} = metadata), do: {:ok, metadata}
  defp normalize_metadata(nil), do: {:ok, %{}}
  defp normalize_metadata(other), do: {:error, {:invalid_capability_metadata, other}}

  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
