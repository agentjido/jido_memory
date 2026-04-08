defmodule Jido.Memory.ProviderRef do
  @moduledoc """
  Normalized provider reference used by runtime dispatch.
  """

  alias Jido.Memory.{Provider.Basic, ProviderRegistry}

  @schema Zoi.struct(
            __MODULE__,
            %{
              key: Zoi.atom(description: "Canonical provider key") |> Zoi.optional(),
              module: Zoi.atom(description: "Concrete provider module") |> Zoi.default(Basic),
              opts:
                Zoi.list(Zoi.any(), description: "Provider initialization options")
                |> Zoi.default([])
            },
            coerce: true
          )

  @required_callbacks [
    validate_config: 1,
    capabilities: 1,
    remember: 3,
    get: 3,
    retrieve: 3,
    forget: 3,
    prune: 2,
    info: 2
  ]

  @enforce_keys [:module, :opts]
  defstruct Zoi.Struct.struct_fields(@schema)

  @type t :: %__MODULE__{
          key: atom() | nil,
          module: module(),
          opts: keyword()
        }

  @type provider_input :: t() | atom() | {atom(), keyword()} | nil

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec normalize(provider_input()) :: {:ok, t()} | {:error, term()}
  def normalize(nil), do: validate(%__MODULE__{key: :basic, module: Basic, opts: []})
  def normalize(%__MODULE__{} = provider), do: validate(provider)

  def normalize({provider, opts}) when is_atom(provider) and is_list(opts) do
    with {:ok, {key, module}} <- resolve_provider(provider) do
      validate(%__MODULE__{key: key, module: module, opts: opts})
    end
  end

  def normalize(provider) when is_atom(provider) do
    with {:ok, {key, module}} <- resolve_provider(provider) do
      validate(%__MODULE__{key: key, module: module, opts: []})
    end
  end

  def normalize(_), do: {:error, :invalid_provider}

  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{key: key, module: module, opts: opts}) when is_atom(module) and is_list(opts) do
    with {:ok, loaded} <- ensure_loaded(module),
         :ok <- ensure_callbacks(loaded),
         :ok <- loaded.validate_config(opts) do
      {:ok, %__MODULE__{key: key || ProviderRegistry.key_for(loaded), module: loaded, opts: opts}}
    end
  end

  def validate(_), do: {:error, :invalid_provider}

  defp resolve_provider(provider) when is_atom(provider) do
    case ProviderRegistry.resolve(provider) do
      {:ok, module} -> {:ok, {ProviderRegistry.key_for(provider) || ProviderRegistry.key_for(module), module}}
    end
  end

  defp ensure_loaded(module) do
    case Code.ensure_loaded(module) do
      {:module, loaded} -> {:ok, loaded}
      {:error, reason} -> {:error, {:provider_not_loaded, module, reason}}
    end
  end

  defp ensure_callbacks(module) do
    missing =
      Enum.reject(@required_callbacks, fn {name, arity} ->
        function_exported?(module, name, arity)
      end)

    if missing == [] do
      :ok
    else
      {:error, {:invalid_provider, {module, missing}}}
    end
  end
end
