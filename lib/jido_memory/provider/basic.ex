defmodule Jido.Memory.Provider.Basic do
  @moduledoc """
  Default provider backed by `Jido.Memory.Store`.
  """

  @behaviour Jido.Memory.Provider

  alias Jido.Memory.{Query, Record, Store}

  @default_store {Jido.Memory.Store.ETS, [table: :jido_memory]}
  @core_capabilities %{
    core: true,
    retrieval: %{explainable: false, active: false, memory_types: false, provider_extensions: false},
    lifecycle: %{consolidate: false, inspect: false},
    ingestion: %{batch: false, multimodal: false, routed: false, access: :none},
    operations: %{},
    governance: %{protected_memory: false, exact_preservation: false, access: :none},
    hooks: %{}
  }

  @type context :: %{
          namespace: String.t(),
          store_mod: module(),
          store_opts: keyword(),
          now: integer(),
          plugin_state: map()
        }

  @impl true
  def validate_config(opts) when is_list(opts) do
    namespace = Keyword.get(opts, :namespace)
    store = Keyword.get(opts, :store)
    store_opts = Keyword.get(opts, :store_opts, [])

    with :ok <- validate_namespace(namespace),
         :ok <- validate_store(store),
         true <- is_list(store_opts) do
      :ok
    else
      false -> {:error, :invalid_store_opts}
      {:error, _} = error -> error
    end
  end

  def validate_config(_opts), do: {:error, :invalid_provider_opts}

  @impl true
  def child_specs(_opts), do: []

  @impl true
  def init(opts) do
    with :ok <- validate_config(opts),
         {:ok, {store_mod, store_opts}} <- normalize_default_store(opts),
         :ok <- store_mod.ensure_ready(store_opts) do
      {:ok,
       %{
         provider: __MODULE__,
         defaults: %{
           namespace: normalize_optional_namespace(Keyword.get(opts, :namespace)),
           store: {store_mod, store_opts}
         },
         capabilities: @core_capabilities
       }}
    end
  end

  @impl true
  def capabilities(provider_meta), do: Map.get(provider_meta, :capabilities, @core_capabilities)

  @impl true
  def remember(target, attrs, opts) when is_list(attrs), do: remember(target, Map.new(attrs), opts)

  def remember(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    with {:ok, context} <- resolve_context(target, attrs, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, record} <- build_record(attrs, context.namespace, context.now) do
      context.store_mod.put(record, context.store_opts)
    end
  end

  def remember(_target, _attrs, _opts), do: {:error, :invalid_attrs}

  @impl true
  def get(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{}, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts) do
      Store.fetch(context.store_mod, {context.namespace, id}, context.store_opts)
    end
  end

  def get(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def retrieve(target, %Query{} = query, opts) when is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{namespace: query.namespace}, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, effective_query} <- attach_namespace(query, context.namespace) do
      context.store_mod.query(effective_query, context.store_opts)
    end
  end

  def retrieve(target, query_attrs, opts) when is_list(query_attrs),
    do: retrieve(target, Map.new(query_attrs), opts)

  def retrieve(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with {:ok, context} <- resolve_context(target, query_attrs, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, query} <- build_query(query_attrs, context.namespace) do
      context.store_mod.query(query, context.store_opts)
    end
  end

  def retrieve(_target, _query, _opts), do: {:error, :invalid_query}

  @impl true
  def forget(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{}, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts) do
      case context.store_mod.get({context.namespace, id}, context.store_opts) do
        {:ok, _record} ->
          :ok = context.store_mod.delete({context.namespace, id}, context.store_opts)
          {:ok, true}

        :not_found ->
          {:ok, false}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def forget(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def prune(target, opts) when is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{}, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts) do
      context.store_mod.prune_expired(context.store_opts)
    end
  end

  @impl true
  def info(provider_meta, :all), do: {:ok, provider_meta}

  def info(provider_meta, fields) when is_list(fields) do
    {:ok, Map.take(provider_meta, fields)}
  end

  def info(_provider_meta, _fields), do: {:error, :invalid_info_fields}

  @doc false
  @spec resolve_context(map() | struct(), map(), keyword()) :: {:ok, context()} | {:error, term()}
  def resolve_context(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    provider_opts = normalize_keyword(Keyword.get(opts, :provider_opts, []))
    plugin_state = plugin_state(target)
    now = Keyword.get(opts, :now, System.system_time(:millisecond))

    with {:ok, namespace} <- resolve_namespace(target, attrs, opts, provider_opts, plugin_state),
         {:ok, {store_mod, store_opts}} <- resolve_store(attrs, opts, provider_opts, plugin_state) do
      {:ok,
       %{
         namespace: namespace,
         store_mod: store_mod,
         store_opts: store_opts,
         now: now,
         plugin_state: plugin_state
       }}
    end
  end

  @spec resolve_namespace(map() | struct(), map(), keyword(), keyword(), map()) ::
          {:ok, String.t()} | {:error, term()}
  defp resolve_namespace(target, attrs, opts, provider_opts, plugin_state) do
    explicit = pick_value(opts, attrs, :namespace)
    from_plugin = map_get(plugin_state, :namespace)
    from_provider = Keyword.get(provider_opts, :namespace)

    resolved =
      cond do
        present_string?(explicit) -> String.trim(explicit)
        present_string?(from_plugin) -> String.trim(from_plugin)
        present_string?(from_provider) -> String.trim(from_provider)
        is_binary(target_id(target)) -> "agent:" <> target_id(target)
        true -> nil
      end

    if is_binary(resolved), do: {:ok, resolved}, else: {:error, :namespace_required}
  end

  @spec resolve_store(map(), keyword(), keyword(), map()) ::
          {:ok, {module(), keyword()}} | {:error, term()}
  defp resolve_store(attrs, opts, provider_opts, plugin_state) do
    explicit_store = pick_value(opts, attrs, :store)
    explicit_store_opts = pick_value(opts, attrs, :store_opts, [])
    provider_store = Keyword.get(provider_opts, :store)
    provider_store_opts = Keyword.get(provider_opts, :store_opts, [])
    plugin_store = map_get(plugin_state, :store)

    store_value =
      cond do
        not is_nil(explicit_store) -> explicit_store
        not is_nil(plugin_store) -> plugin_store
        not is_nil(provider_store) -> provider_store
        true -> @default_store
      end

    with {:ok, {store_mod, base_opts}} <- Store.normalize_store(store_value),
         {:ok, merged_provider_opts} <- normalize_store_opts(base_opts, provider_store_opts),
         {:ok, merged_opts} <- normalize_store_opts(merged_provider_opts, explicit_store_opts) do
      {:ok, {store_mod, merged_opts}}
    end
  end

  @spec build_record(map(), String.t(), integer()) :: {:ok, Record.t()} | {:error, term()}
  defp build_record(attrs, namespace, now) do
    attrs =
      attrs
      |> Map.drop([:provider, "provider"])
      |> Map.put(:namespace, namespace)
      |> Map.put_new(:observed_at, now)

    Record.new(attrs, now: now)
  end

  @spec build_query(map(), String.t()) :: {:ok, Query.t()} | {:error, term()}
  defp build_query(attrs, namespace) do
    attrs =
      attrs
      |> Map.drop([:provider, "provider"])
      |> Map.put_new(:namespace, namespace)

    Query.new(attrs)
  end

  @spec attach_namespace(Query.t(), String.t()) :: {:ok, Query.t()} | {:error, term()}
  defp attach_namespace(%Query{namespace: nil} = query, namespace) when is_binary(namespace),
    do: {:ok, %{query | namespace: namespace}}

  defp attach_namespace(%Query{namespace: query_namespace} = query, runtime_namespace)
       when is_binary(query_namespace) and is_binary(runtime_namespace),
       do: {:ok, query}

  defp attach_namespace(%Query{}, _), do: {:error, :namespace_required}

  @spec normalize_store_opts(keyword(), keyword()) :: {:ok, keyword()} | {:error, term()}
  defp normalize_store_opts(base_opts, override_opts)
       when is_list(base_opts) and is_list(override_opts),
       do: {:ok, Keyword.merge(base_opts, override_opts)}

  defp normalize_store_opts(_base, _override), do: {:error, :invalid_store_opts}

  defp normalize_keyword(opts) when is_list(opts), do: opts
  defp normalize_keyword(_opts), do: []

  defp plugin_state(%{state: %{} = state}),
    do: Map.get(state, Jido.Memory.Runtime.plugin_state_key(), %{}) |> normalize_map()

  defp plugin_state(%{} = map),
    do: Map.get(map, Jido.Memory.Runtime.plugin_state_key(), %{}) |> normalize_map()

  defp plugin_state(_), do: %{}

  defp target_id(%{id: id}) when is_binary(id), do: id
  defp target_id(%{agent: %{id: id}}) when is_binary(id), do: id
  defp target_id(_), do: nil

  defp pick_value(opts, attrs, key, default \\ nil) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
    end
  end

  defp map_get(map, key, default \\ nil)

  defp map_get(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_), do: %{}

  defp validate_namespace(nil), do: :ok
  defp validate_namespace(value) when is_binary(value) or is_atom(value), do: :ok
  defp validate_namespace(_value), do: {:error, :invalid_namespace}

  defp validate_store(nil), do: :ok

  defp validate_store(store) do
    case Store.normalize_store(store) do
      {:ok, _normalized} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_default_store(opts) do
    store = Keyword.get(opts, :store, @default_store)
    store_opts = Keyword.get(opts, :store_opts, [])

    with {:ok, {store_mod, base_opts}} <- Store.normalize_store(store),
         {:ok, merged_opts} <- normalize_store_opts(base_opts, store_opts) do
      {:ok, {store_mod, merged_opts}}
    end
  end

  defp normalize_optional_namespace(nil), do: nil
  defp normalize_optional_namespace(namespace) when is_binary(namespace), do: String.trim(namespace)
  defp normalize_optional_namespace(namespace) when is_atom(namespace), do: Atom.to_string(namespace)
  defp normalize_optional_namespace(_namespace), do: nil

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false
end
