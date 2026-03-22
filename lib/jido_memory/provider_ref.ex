defmodule Jido.Memory.ProviderRef do
  @moduledoc """
  Normalized provider reference used by the runtime and plugins.
  """

  alias Jido.Memory.Error.InvalidProvider
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Provider.Tiered

  @built_in_aliases %{
    basic: Basic,
    tiered: Tiered
  }

  @required_callbacks [
    validate_config: 1,
    child_specs: 1,
    init: 1,
    capabilities: 1,
    remember: 3,
    get: 3,
    retrieve: 3,
    forget: 3,
    prune: 2,
    info: 2
  ]

  @enforce_keys [:module, :opts]
  defstruct module: Basic, opts: []

  @type t :: %__MODULE__{
          module: module(),
          opts: keyword()
        }

  @spec default() :: t()
  def default, do: %__MODULE__{module: Basic, opts: []}

  @spec required_callbacks() :: keyword(pos_integer())
  def required_callbacks, do: @required_callbacks

  @spec normalize(t() | module() | {module(), keyword()} | nil) :: {:ok, t()} | {:error, term()}
  def normalize(nil), do: {:ok, default()}

  def normalize(%__MODULE__{module: module, opts: opts}) when is_atom(module) and is_list(opts) do
    module = Map.get(@built_in_aliases, module, module)
    validate(%__MODULE__{module: module, opts: opts})
  end

  def normalize({module, opts}) when is_atom(module) and is_list(opts) do
    module = Map.get(@built_in_aliases, module, module)
    validate(%__MODULE__{module: module, opts: opts})
  end

  def normalize(module) when is_atom(module) do
    module = Map.get(@built_in_aliases, module, module)
    validate(%__MODULE__{module: module, opts: []})
  end

  def normalize(other), do: {:error, InvalidProvider.exception(provider: other, reason: :invalid)}

  @spec resolve(map(), keyword(), map()) :: {:ok, t()} | {:error, term()}
  def resolve(attrs, opts, plugin_state) when is_map(attrs) and is_list(opts) and is_map(plugin_state) do
    provider_input =
      case Keyword.fetch(opts, :provider) do
        {:ok, provider} ->
          provider

        :error ->
          Map.get(attrs, :provider, Map.get(attrs, "provider", map_get(plugin_state, :provider)))
      end

    provider_opts =
      case Keyword.fetch(opts, :provider_opts) do
        {:ok, runtime_provider_opts} ->
          runtime_provider_opts

        :error ->
          Map.get(attrs, :provider_opts, Map.get(attrs, "provider_opts", []))
      end

    normalize_provider_input(provider_input, provider_opts)
  end

  defp normalize_provider_input(nil, _provider_opts), do: normalize(nil)

  defp normalize_provider_input(%__MODULE__{} = provider_ref, _provider_opts),
    do: normalize(provider_ref)

  defp normalize_provider_input({module, opts}, _provider_opts) when is_atom(module) and is_list(opts),
    do: normalize({module, opts})

  defp normalize_provider_input(module, provider_opts) when is_atom(module) and is_list(provider_opts),
    do: normalize({module, provider_opts})

  defp normalize_provider_input(other, _provider_opts), do: normalize(other)

  @spec runtime_opts(t(), keyword()) :: keyword()
  def runtime_opts(%__MODULE__{opts: provider_opts}, opts) when is_list(opts) do
    opts
    |> Keyword.delete(:provider)
    |> Keyword.put(:provider_opts, provider_opts)
  end

  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{module: module, opts: opts} = ref) when is_atom(module) and is_list(opts) do
    with {:ok, loaded} <- ensure_loaded(module),
         :ok <- ensure_behaviour(loaded),
         :ok <- loaded.validate_config(opts) do
      {:ok, %{ref | module: loaded}}
    end
  end

  defp ensure_loaded(module) do
    case Code.ensure_loaded(module) do
      {:module, loaded} ->
        {:ok, loaded}

      {:error, reason} ->
        {:error, InvalidProvider.exception(provider: module, reason: {:load_failed, reason})}
    end
  end

  defp ensure_behaviour(module) do
    missing =
      Enum.reject(@required_callbacks, fn {name, arity} ->
        function_exported?(module, name, arity)
      end)

    if missing == [] do
      :ok
    else
      {:error, InvalidProvider.exception(provider: module, reason: {:missing_callbacks, missing})}
    end
  end

  defp map_get(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
