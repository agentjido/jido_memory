defmodule Jido.Memory.CapabilitySet do
  @moduledoc """
  Normalized capability descriptor for a memory provider.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              provider: Zoi.atom(description: "Concrete provider module or alias") |> Zoi.optional(),
              capabilities:
                Zoi.list(Zoi.atom(), description: "Supported capability atoms")
                |> Zoi.default([]),
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
    with {:ok, provider} <- normalize_provider(get_attr(attrs, :provider)),
         {:ok, capabilities} <- normalize_capabilities(get_attr(attrs, :capabilities, [])),
         {:ok, metadata} <- normalize_metadata(get_attr(attrs, :metadata, %{})) do
      {:ok,
       struct!(__MODULE__, %{
         provider: provider,
         capabilities: capabilities,
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
  @spec supports?(t(), atom()) :: boolean()
  def supports?(%__MODULE__{capabilities: capabilities}, capability) when is_atom(capability) do
    capability in capabilities
  end

  defp normalize_provider(nil), do: {:ok, nil}
  defp normalize_provider(provider) when is_atom(provider), do: {:ok, provider}
  defp normalize_provider(other), do: {:error, {:invalid_provider, other}}

  defp normalize_capabilities(values) when is_list(values) do
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

  defp normalize_capabilities(nil), do: {:ok, []}
  defp normalize_capabilities(other), do: {:error, {:invalid_capabilities, other}}

  defp normalize_metadata(%{} = metadata), do: {:ok, metadata}
  defp normalize_metadata(nil), do: {:ok, %{}}
  defp normalize_metadata(other), do: {:error, {:invalid_capability_metadata, other}}

  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
