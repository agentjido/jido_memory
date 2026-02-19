defmodule Jido.Memory.Runtime do
  @moduledoc """
  Facade API for writing and retrieving memory records.

  Works with either:
  - agent/context inputs that already carry memory plugin state, or
  - explicit `namespace` and `store` options for non-plugin callers.
  """

  alias Jido.Memory.Query
  alias Jido.Memory.Record
  alias Jido.Memory.Store

  @default_store {Jido.Memory.Store.ETS, [table: :jido_memory]}
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
    with {:ok, runtime} <- resolve_runtime(target, attrs, opts),
         :ok <- runtime.store_mod.ensure_ready(runtime.store_opts),
         {:ok, record} <- build_record(attrs, runtime.namespace, runtime.now),
         {:ok, stored} <- runtime.store_mod.put(record, runtime.store_opts) do
      {:ok, stored}
    end
  end

  def remember(_target, _attrs, _opts), do: {:error, :invalid_attrs}

  @doc "Reads a single memory record by id."
  @spec get(target(), String.t(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def get(target, id, opts \\ [])

  def get(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, runtime} <- resolve_runtime(target, %{}, opts),
         :ok <- runtime.store_mod.ensure_ready(runtime.store_opts),
         {:ok, record} <-
           Store.fetch(runtime.store_mod, {runtime.namespace, id}, runtime.store_opts) do
      {:ok, record}
    end
  end

  def get(_target, _id, _opts), do: {:error, :invalid_id}

  @doc "Deletes a memory record by id and returns whether it existed."
  @spec forget(target(), String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def forget(target, id, opts \\ [])

  def forget(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, runtime} <- resolve_runtime(target, %{}, opts),
         :ok <- runtime.store_mod.ensure_ready(runtime.store_opts) do
      case runtime.store_mod.get({runtime.namespace, id}, runtime.store_opts) do
        {:ok, _record} ->
          :ok = runtime.store_mod.delete({runtime.namespace, id}, runtime.store_opts)
          {:ok, true}

        :not_found ->
          {:ok, false}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def forget(_target, _id, _opts), do: {:error, :invalid_id}

  @doc "Queries memory records by structured filters."
  @spec recall(target(), Query.t() | map() | keyword()) :: {:ok, [Record.t()]} | {:error, term()}
  def recall(target, %Query{} = query) do
    with {:ok, runtime} <- resolve_runtime(target, %{namespace: query.namespace}, []),
         :ok <- runtime.store_mod.ensure_ready(runtime.store_opts),
         {:ok, effective_query} <- attach_namespace(query, runtime.namespace),
         {:ok, records} <- runtime.store_mod.query(effective_query, runtime.store_opts) do
      {:ok, records}
    end
  end

  def recall(target, query_attrs) when is_list(query_attrs),
    do: recall(target, Map.new(query_attrs))

  def recall(target, query_attrs) when is_map(query_attrs) do
    with {:ok, runtime} <- resolve_runtime(target, query_attrs, []),
         :ok <- runtime.store_mod.ensure_ready(runtime.store_opts),
         {:ok, query} <- build_query(query_attrs, runtime.namespace),
         {:ok, records} <- runtime.store_mod.query(query, runtime.store_opts) do
      {:ok, records}
    end
  end

  def recall(_target, _query), do: {:error, :invalid_query}

  @doc "Prunes expired records in the active store."
  @spec prune_expired(target(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def prune_expired(target, opts \\ []) when is_list(opts) do
    with {:ok, runtime} <- resolve_runtime(target, %{}, opts),
         :ok <- runtime.store_mod.ensure_ready(runtime.store_opts),
         {:ok, count} <- runtime.store_mod.prune_expired(runtime.store_opts) do
      {:ok, count}
    end
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
    plugin_state = plugin_state(target)
    now = Keyword.get(opts, :now, System.system_time(:millisecond))

    with {:ok, namespace} <- resolve_namespace(target, attrs, opts, plugin_state),
         {:ok, {store_mod, store_opts}} <- resolve_store(attrs, opts, plugin_state) do
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

  @doc "Resolves namespace using explicit values, plugin state, then agent id fallback."
  @spec resolve_namespace(target(), map(), keyword(), map()) ::
          {:ok, String.t()} | {:error, term()}
  def resolve_namespace(target, attrs, opts, plugin_state) do
    explicit = pick_value(opts, attrs, :namespace)
    from_plugin = map_get(plugin_state, :namespace)

    resolved =
      cond do
        is_binary(explicit) and String.trim(explicit) != "" -> String.trim(explicit)
        is_binary(from_plugin) and String.trim(from_plugin) != "" -> String.trim(from_plugin)
        is_binary(target_id(target)) -> "agent:" <> target_id(target)
        true -> nil
      end

    if is_binary(resolved), do: {:ok, resolved}, else: {:error, :namespace_required}
  end

  @doc "Resolves store from explicit values, plugin state, then defaults."
  @spec resolve_store(map(), keyword(), map()) :: {:ok, {module(), keyword()}} | {:error, term()}
  def resolve_store(attrs, opts, plugin_state) do
    explicit_store = pick_value(opts, attrs, :store)
    explicit_store_opts = pick_value(opts, attrs, :store_opts, [])

    plugin_store = map_get(plugin_state, :store)

    store_value =
      cond do
        not is_nil(explicit_store) ->
          explicit_store

        not is_nil(plugin_store) ->
          plugin_store

        true ->
          @default_store
      end

    with {:ok, {store_mod, base_opts}} <- Store.normalize_store(store_value),
         {:ok, merged_opts} <- normalize_store_opts(base_opts, explicit_store_opts) do
      {:ok, {store_mod, merged_opts}}
    end
  end

  @spec build_record(map(), String.t(), integer()) :: {:ok, Record.t()} | {:error, term()}
  defp build_record(attrs, namespace, now) do
    attrs =
      attrs
      |> Map.put(:namespace, namespace)
      |> Map.put_new(:observed_at, now)

    Record.new(attrs, now: now)
  end

  @spec build_query(map(), String.t()) :: {:ok, Query.t()} | {:error, term()}
  defp build_query(attrs, namespace) do
    attrs = Map.put_new(attrs, :namespace, namespace)
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

  @spec plugin_state(target()) :: map()
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

  @spec target_id(target()) :: String.t() | nil
  defp target_id(%{id: id}) when is_binary(id), do: id
  defp target_id(%{agent: %{id: id}}) when is_binary(id), do: id
  defp target_id(_), do: nil

  @spec pick_value(keyword(), map(), atom(), term()) :: term()
  defp pick_value(opts, attrs, key, default \\ nil) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
    end
  end

  @spec map_get(map(), atom(), term()) :: term()
  defp map_get(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
