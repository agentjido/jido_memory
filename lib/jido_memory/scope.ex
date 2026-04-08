defmodule Jido.Memory.Scope do
  @moduledoc """
  Provider-neutral memory scope metadata.
  """

  alias Jido.Memory.ProviderRegistry

  @schema Zoi.struct(
            __MODULE__,
            %{
              namespace: Zoi.string(description: "Logical memory namespace") |> Zoi.optional(),
              provider: Zoi.atom(description: "Concrete provider module or alias") |> Zoi.optional(),
              provider_key: Zoi.atom(description: "Canonical provider key") |> Zoi.optional(),
              provider_name:
                Zoi.string(description: "Normalized provider display name")
                |> Zoi.optional(),
              metadata: Zoi.map(description: "Additional scope metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the scope schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds and normalizes a scope."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    provider = get_attr(attrs, :provider)
    namespace = normalize_optional_string(get_attr(attrs, :namespace))
    provider_key = normalize_provider_key(get_attr(attrs, :provider_key), provider)
    provider_name = normalize_provider_name(get_attr(attrs, :provider_name), provider)
    metadata = normalize_metadata(get_attr(attrs, :metadata, %{}))

    with {:ok, namespace} <- namespace,
         {:ok, provider} <- normalize_provider(provider),
         {:ok, provider_key} <- provider_key,
         {:ok, provider_name} <- provider_name,
         {:ok, metadata} <- metadata do
      {:ok,
       struct!(__MODULE__, %{
         namespace: namespace,
         provider: provider,
         provider_key: provider_key,
         provider_name: provider_name,
         metadata: metadata
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_scope}

  @doc "Builds and normalizes a scope, raising on error."
  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, scope} -> scope
      {:error, reason} -> raise ArgumentError, "invalid memory scope: #{inspect(reason)}"
    end
  end

  @doc "Builds a scope from resolved provider metadata."
  @spec from_provider(module() | atom() | nil, keyword()) :: t()
  def from_provider(provider, provider_opts \\ []) when is_list(provider_opts) do
    new!(%{
      namespace: Keyword.get(provider_opts, :namespace),
      provider: provider,
      provider_key: ProviderRegistry.key_for(provider),
      metadata: %{provider_opts: provider_opts}
    })
  end

  @doc "Returns a normalized provider display name."
  @spec provider_name(module() | atom() | nil) :: String.t() | nil
  def provider_name(nil), do: nil

  def provider_name(provider) when is_atom(provider) do
    provider
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> Macro.underscore()
  end

  def provider_name(_provider), do: nil

  defp normalize_provider(nil), do: {:ok, nil}
  defp normalize_provider(provider) when is_atom(provider), do: {:ok, provider}
  defp normalize_provider(other), do: {:error, {:invalid_provider, other}}

  defp normalize_provider_key(nil, provider) when is_atom(provider), do: {:ok, ProviderRegistry.key_for(provider)}
  defp normalize_provider_key(nil, _provider), do: {:ok, nil}
  defp normalize_provider_key(value, _provider) when is_atom(value), do: {:ok, value}
  defp normalize_provider_key(other, _provider), do: {:error, {:invalid_provider_key, other}}

  defp normalize_provider_name(nil, provider), do: {:ok, provider_name(provider)}

  defp normalize_provider_name(value, _provider) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: {:ok, nil}, else: {:ok, trimmed}
  end

  defp normalize_provider_name(other, _provider), do: {:error, {:invalid_provider_name, other}}

  defp normalize_metadata(%{} = metadata), do: {:ok, metadata}
  defp normalize_metadata(nil), do: {:ok, %{}}
  defp normalize_metadata(other), do: {:error, {:invalid_scope_metadata, other}}

  defp normalize_optional_string(nil), do: {:ok, nil}

  defp normalize_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: {:ok, nil}, else: {:ok, trimmed}
  end

  defp normalize_optional_string(other), do: {:error, {:invalid_scope_value, other}}

  defp get_attr(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
