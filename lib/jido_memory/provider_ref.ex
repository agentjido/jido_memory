defmodule Jido.Memory.ProviderRef do
  @moduledoc """
  Normalized provider reference used by the runtime and plugins.

  Provider precedence is explicit:

  1. runtime opts
  2. request attrs
  3. plugin state
  4. default built-in provider

  Alias precedence follows the same runtime, attrs, then plugin-state order.
  Built-in aliases are always available and optional external aliases can be
  passed through `provider_aliases`.
  """

  alias Jido.Memory.Error.InvalidProvider
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.ProviderRegistry

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

  @type provider_input :: t() | module() | {module(), keyword()} | nil
  @type provider_aliases_input :: keyword(module()) | map() | nil

  @spec default() :: t()
  def default, do: %__MODULE__{module: Basic, opts: []}

  @spec required_callbacks() :: keyword(pos_integer())
  def required_callbacks, do: @required_callbacks

  @spec source_precedence() :: [atom()]
  def source_precedence, do: [:runtime_opts, :attrs, :plugin_state, :default]

  @spec alias_source_precedence() :: [atom()]
  def alias_source_precedence, do: [:runtime_opts, :attrs, :plugin_state, :built_in]

  @spec normalize(provider_input()) :: {:ok, t()} | {:error, term()}
  def normalize(provider), do: normalize(provider, nil)

  @spec normalize(provider_input(), provider_aliases_input()) :: {:ok, t()} | {:error, term()}
  def normalize(nil, _provider_aliases), do: {:ok, default()}

  def normalize(%__MODULE__{module: module, opts: opts}, provider_aliases)
      when is_atom(module) and is_list(opts) do
    with {:ok, module} <- resolve_module_or_alias(module, provider_aliases) do
      validate(%__MODULE__{module: module, opts: opts})
    end
  end

  def normalize({module, opts}, provider_aliases) when is_atom(module) and is_list(opts) do
    with {:ok, module} <- resolve_module_or_alias(module, provider_aliases) do
      validate(%__MODULE__{module: module, opts: opts})
    end
  end

  def normalize(module, provider_aliases) when is_atom(module) do
    with {:ok, module} <- resolve_module_or_alias(module, provider_aliases) do
      validate(%__MODULE__{module: module, opts: []})
    end
  end

  def normalize(other, _provider_aliases),
    do: {:error, InvalidProvider.exception(provider: other, reason: :invalid)}

  @spec resolve(map(), keyword(), map()) :: {:ok, t()} | {:error, term()}
  def resolve(attrs, opts, plugin_state) when is_map(attrs) and is_list(opts) and is_map(plugin_state) do
    provider_input = resolve_provider_input(attrs, opts, plugin_state)
    provider_opts = resolve_provider_opts(attrs, opts)

    with {:ok, provider_aliases} <- resolve_provider_aliases(attrs, opts, plugin_state),
         :ok <- validate_provider_opts(provider_input, provider_opts) do
      normalize_provider_input(provider_input, provider_opts, provider_aliases)
    end
  end

  defp normalize_provider_input(nil, _provider_opts, _provider_aliases), do: normalize(nil)

  defp normalize_provider_input(%__MODULE__{} = provider_ref, _provider_opts, provider_aliases),
    do: normalize(provider_ref, provider_aliases)

  defp normalize_provider_input({module, opts}, _provider_opts, provider_aliases)
       when is_atom(module) and is_list(opts),
       do: normalize({module, opts}, provider_aliases)

  defp normalize_provider_input(module, provider_opts, provider_aliases)
       when is_atom(module) and is_list(provider_opts),
       do: normalize({module, provider_opts}, provider_aliases)

  defp normalize_provider_input(other, _provider_opts, provider_aliases), do: normalize(other, provider_aliases)

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

  defp resolve_module_or_alias(module_or_alias, provider_aliases) do
    case ProviderRegistry.resolve_alias(module_or_alias, provider_aliases) do
      {:ok, module} -> {:ok, module}
      :error -> {:ok, module_or_alias}
      {:error, _reason} = error -> error
    end
  end

  defp resolve_provider_input(attrs, opts, plugin_state) do
    case Keyword.fetch(opts, :provider) do
      {:ok, provider} ->
        provider

      :error ->
        Map.get(attrs, :provider, Map.get(attrs, "provider", map_get(plugin_state, :provider)))
    end
  end

  defp resolve_provider_opts(attrs, opts) do
    case Keyword.fetch(opts, :provider_opts) do
      {:ok, runtime_provider_opts} ->
        runtime_provider_opts

      :error ->
        Map.get(attrs, :provider_opts, Map.get(attrs, "provider_opts", []))
    end
  end

  defp resolve_provider_aliases(attrs, opts, plugin_state) do
    aliases_input =
      case Keyword.fetch(opts, :provider_aliases) do
        {:ok, runtime_aliases} ->
          runtime_aliases

        :error ->
          Map.get(
            attrs,
            :provider_aliases,
            Map.get(attrs, "provider_aliases", map_get(plugin_state, :provider_aliases, nil))
          )
      end

    ProviderRegistry.normalize_aliases(aliases_input)
  end

  defp validate_provider_opts(provider_input, provider_opts)
       when provider_input in [nil] or is_list(provider_opts),
       do: :ok

  defp validate_provider_opts(%__MODULE__{}, _provider_opts), do: :ok
  defp validate_provider_opts({module, opts}, _provider_opts) when is_atom(module) and is_list(opts), do: :ok
  defp validate_provider_opts(module, _provider_opts) when is_atom(module), do: {:error, :invalid_provider_opts}
  defp validate_provider_opts(_provider_input, _provider_opts), do: :ok

  defp map_get(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
