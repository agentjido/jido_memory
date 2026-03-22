defmodule Jido.Memory.Runtime do
  @moduledoc """
  Facade API for writing and retrieving memory records.

  Works with either:
  - agent/context inputs that already carry memory plugin state, or
  - explicit `namespace` and `store` options for non-plugin callers.
  """

  alias Jido.Memory.Capabilities
  alias Jido.Memory.Error.{InvalidProvider, UnsupportedCapability}
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.ProviderRef
  alias Jido.Memory.Query
  alias Jido.Memory.Record

  @plugin_state_key :__memory__

  @type target :: map() | struct()

  @doc "Returns the plugin state key used for memory metadata."
  @spec plugin_state_key() :: atom()
  def plugin_state_key, do: @plugin_state_key

  @doc "Writes a memory record."
  @spec remember(target(), map() | keyword(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def remember(target, attrs, opts \\ [])

  def remember(target, attrs, opts) when is_list(attrs),
    do: remember(target, Map.new(attrs), opts)

  def remember(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    call_provider(target, attrs, opts, fn provider_ref, runtime_opts ->
      provider_ref.module.remember(target, attrs, runtime_opts)
    end)
  end

  def remember(_target, _attrs, _opts), do: {:error, :invalid_attrs}

  @doc "Reads a single memory record by id."
  @spec get(target(), String.t(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def get(target, id, opts \\ [])

  def get(target, id, opts) when is_binary(id) and is_list(opts) do
    call_provider(target, %{}, opts, fn provider_ref, runtime_opts ->
      provider_ref.module.get(target, id, runtime_opts)
    end)
  end

  def get(_target, _id, _opts), do: {:error, :invalid_id}

  @doc "Deletes a memory record by id and returns whether it existed."
  @spec forget(target(), String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def forget(target, id, opts \\ [])

  def forget(target, id, opts) when is_binary(id) and is_list(opts) do
    call_provider(target, %{}, opts, fn provider_ref, runtime_opts ->
      provider_ref.module.forget(target, id, runtime_opts)
    end)
  end

  def forget(_target, _id, _opts), do: {:error, :invalid_id}

  @doc "Queries memory records by structured filters through the canonical provider path."
  @spec retrieve(target(), Query.t() | map() | keyword(), keyword()) ::
          {:ok, [Record.t()]} | {:error, term()}
  def retrieve(target, query, opts \\ [])

  def retrieve(target, query, opts) when is_list(query),
    do: retrieve(target, Map.new(query), opts)

  def retrieve(target, %Query{} = query, opts) when is_list(opts) do
    call_provider(target, %{namespace: query.namespace}, opts, fn provider_ref, runtime_opts ->
      provider_ref.module.retrieve(target, query, runtime_opts)
    end)
  end

  def retrieve(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    call_provider(target, query_attrs, opts, fn provider_ref, runtime_opts ->
      provider_ref.module.retrieve(target, query_attrs, runtime_opts)
    end)
  end

  def retrieve(_target, _query, _opts), do: {:error, :invalid_query}

  @doc "Queries memory records by structured filters."
  @spec recall(target(), Query.t() | map() | keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def recall(target, query), do: retrieve(target, query, [])

  @doc "Prunes expired records in the active store."
  @spec prune_expired(target(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def prune_expired(target, opts \\ []) when is_list(opts) do
    call_provider(target, %{}, opts, fn provider_ref, runtime_opts ->
      provider_ref.module.prune(target, runtime_opts)
    end)
  end

  @doc "Infers namespace and store for plugin and action code paths."
  @spec resolve_runtime(target(), map(), keyword()) ::
          {:ok,
           %{
             namespace: String.t(),
             store_mod: module(),
             store_opts: keyword(),
             now: integer(),
             plugin_state: map()
           }}
          | {:error, term()}
  def resolve_runtime(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    Basic.resolve_context(target, attrs, opts)
  end

  @doc "Returns provider capabilities for the effective runtime path."
  @spec capabilities(target(), keyword()) :: {:ok, map()} | {:error, term()}
  def capabilities(target, opts \\ []) when is_list(opts) do
    with {:ok, provider_ref} <- resolve_provider(target, %{}, opts),
         {:ok, provider_meta} <- provider_meta(provider_ref) do
      {:ok, provider_ref.module.capabilities(provider_meta) |> Capabilities.normalize()}
    else
      {:error, reason} -> normalize_error(reason)
    end
  end

  @doc "Returns provider metadata for the effective runtime path."
  @spec info(target(), :all | [atom()], keyword()) :: {:ok, map()} | {:error, term()}
  def info(target, fields \\ :all, opts \\ []) when is_list(opts) do
    with {:ok, provider_ref} <- resolve_provider(target, %{}, opts),
         {:ok, provider_meta} <- provider_meta(provider_ref),
         {:ok, info} <- provider_ref.module.info(provider_meta, fields) do
      {:ok, info}
    else
      {:error, reason} -> normalize_error(reason)
    end
  end

  @doc "Runs provider lifecycle consolidation when supported."
  @spec consolidate(target(), keyword()) :: {:ok, map()} | {:error, term()}
  def consolidate(target, opts \\ []) when is_list(opts) do
    dispatch_capability(
      target,
      %{},
      opts,
      :consolidate,
      [:lifecycle, :consolidate],
      & &1.module.consolidate(target, &2)
    )
  end

  @doc "Returns retrieval explanation details when supported."
  @spec explain_retrieval(target(), Query.t() | map() | keyword(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def explain_retrieval(target, query, opts \\ [])

  def explain_retrieval(target, query, opts) when is_list(query),
    do: explain_retrieval(target, Map.new(query), opts)

  def explain_retrieval(target, %Query{} = query, opts) when is_list(opts) do
    dispatch_capability(
      target,
      %{namespace: query.namespace},
      opts,
      :explain_retrieval,
      [:retrieval, :explainable],
      & &1.module.explain_retrieval(target, query, &2)
    )
  end

  def explain_retrieval(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    dispatch_capability(
      target,
      query_attrs,
      opts,
      :explain_retrieval,
      [:retrieval, :explainable],
      & &1.module.explain_retrieval(target, query_attrs, &2)
    )
  end

  def explain_retrieval(_target, _query, _opts), do: {:error, :invalid_query}

  defp call_provider(target, attrs, opts, callback) do
    case resolve_provider(target, attrs, opts) do
      {:ok, provider_ref} ->
        callback.(provider_ref, ProviderRef.runtime_opts(provider_ref, opts))
        |> normalize_result()

      {:error, reason} ->
        normalize_error(reason)
    end
  end

  defp dispatch_capability(target, attrs, opts, capability, capability_path, callback) do
    with {:ok, provider_ref} <- resolve_provider(target, attrs, opts),
         {:ok, provider_meta} <- provider_meta(provider_ref),
         capabilities <- Capabilities.normalize(provider_ref.module.capabilities(provider_meta)),
         true <- Capabilities.supported?(capabilities, capability_path) do
      callback.(provider_ref, ProviderRef.runtime_opts(provider_ref, opts))
      |> normalize_result()
    else
      false ->
        normalize_error(
          UnsupportedCapability.exception(provider: provider_module_name(target, attrs, opts), capability: capability)
        )

      {:error, reason} ->
        normalize_error(reason)
    end
  end

  defp resolve_provider(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    target
    |> plugin_state()
    |> then(&ProviderRef.resolve(attrs, opts, &1))
  end

  defp provider_meta(%ProviderRef{} = provider_ref) do
    provider_ref.module.init(provider_ref.opts)
  end

  defp provider_module_name(target, attrs, opts) do
    case resolve_provider(target, attrs, opts) do
      {:ok, provider_ref} -> provider_ref.module
      {:error, _reason} -> nil
    end
  end

  defp normalize_result({:ok, _value} = ok), do: ok
  defp normalize_result({:error, reason}), do: normalize_error(reason)

  defp normalize_error(%InvalidProvider{provider: provider}),
    do: {:error, {:invalid_provider, provider}}

  defp normalize_error(%UnsupportedCapability{capability: capability}),
    do: {:error, {:unsupported_capability, capability}}

  defp normalize_error(reason), do: {:error, reason}

  defp plugin_state(%{state: %{} = state}) do
    case Map.get(state, @plugin_state_key) do
      %{} = plugin_state -> plugin_state
      _ -> %{}
    end
  end

  defp plugin_state(%{} = map) do
    case Map.get(map, @plugin_state_key) do
      %{} = plugin_state -> plugin_state
      _ -> %{}
    end
  end

  defp plugin_state(_), do: %{}
end
