defmodule Jido.Memory.Provider.Basic do
  @moduledoc """
  Built-in provider that wraps the existing `Jido.Memory.Store` subsystem.
  """

  @behaviour Jido.Memory.Provider
  @behaviour Jido.Memory.Capability.ExplainableRetrieval
  @behaviour Jido.Memory.Capability.Ingestion
  @behaviour Jido.Memory.Capability.Lifecycle

  alias Jido.Memory.{
    Capabilities,
    CapabilitySet,
    ConsolidationResult,
    Explanation,
    Helpers,
    IngestRequest,
    IngestResult,
    ProviderInfo,
    Query,
    Record,
    RetrieveResult,
    Scope,
    Store
  }

  @default_store {Jido.Memory.Store.ETS, [table: :jido_memory]}
  @capabilities [:remember, :get, :retrieve, :forget, :prune, :ingest, :explain_retrieval, :consolidate]
  @capability_descriptor Capabilities.normalize(%{
                           core: true,
                           retrieval: %{
                             explainable: true,
                             active: false,
                             memory_types: false,
                             provider_extensions: false,
                             explanation_scope: :result_reasons
                           },
                           lifecycle: %{consolidate: true, inspect: false},
                           ingestion: %{batch: true, multimodal: false, routed: false, access: :runtime},
                           operations: %{},
                           governance: %{protected_memory: false, exact_preservation: false, access: :none},
                           hooks: %{}
                         })

  @schema Zoi.struct(
            __MODULE__,
            %{
              namespace: Zoi.string(description: "Optional explicit namespace used by this provider"),
              store: Zoi.any(description: "Store declaration (module or {module, opts})"),
              store_opts: Zoi.list(Zoi.any(), description: "Store options") |> Zoi.default([])
            },
            coerce: true
          )

  @type context :: %{
          namespace: String.t(),
          store_mod: module(),
          store_opts: keyword(),
          provider_opts: keyword(),
          now: integer()
        }

  @doc "Returns the provider schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @impl true
  def validate_config(opts) when is_list(opts) do
    namespace = Keyword.get(opts, :namespace)
    store = Keyword.get(opts, :store)
    store_opts = Keyword.get(opts, :store_opts, [])

    with :ok <- validate_provider_opts_shape(opts),
         :ok <- validate_namespace(namespace),
         :ok <- validate_store_opts_shape(store_opts),
         :ok <- validate_store(store, store_opts) do
      :ok
    else
      {:error, _} = error -> error
    end
  end

  def validate_config(_opts), do: {:error, :invalid_provider_opts}

  @impl true
  def capabilities(opts) when is_list(opts) do
    {:ok,
     CapabilitySet.new!(%{
       key: :basic,
       provider: __MODULE__,
       capabilities: @capabilities,
       descriptor: @capability_descriptor,
       metadata: %{provider_opts: opts}
     })}
  end

  @impl true
  def info(opts, _fields) when is_list(opts) do
    {:ok,
     ProviderInfo.new!(%{
       name: "basic",
       key: :basic,
       provider: __MODULE__,
       provider_style: :basic,
       version: version(),
       description: "Provider that persists canonical records through Jido.Memory.Store",
       capabilities: @capabilities,
       capability_descriptor: @capability_descriptor,
       scope: Scope.from_provider(__MODULE__, opts),
       topology: %{
         archetype: :store_backed,
         persistence: :single_store,
         retrieval: %{structured: true, semantic: false}
       },
       advanced_operations: %{},
       surface_boundary: %{
         common_runtime: [
           :remember,
           :get,
           :retrieve,
           :forget,
           :prune_expired,
           :ingest,
           :explain_retrieval,
           :consolidate
         ],
         provider_direct: [],
         plugin: Jido.Memory.BasicPlugin
       },
       defaults: %{
         namespace: Keyword.get(opts, :namespace),
         store: Keyword.get(opts, :store, @default_store),
         store_opts: Keyword.get(opts, :store_opts, [])
       },
       metadata: %{store: Keyword.get(opts, :store, @default_store)}
     })}
  end

  @impl true
  def remember(target, attrs, opts) when is_list(attrs),
    do: remember(target, Map.new(attrs), opts)

  def remember(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    with_context(target, attrs, opts, fn context ->
      with {:ok, record} <- build_record(attrs, context.namespace, context.now) do
        context.store_mod.put(record, context.store_opts)
      end
    end)
  end

  def remember(_target, _attrs, _opts), do: {:error, :invalid_attrs}

  @impl true
  def get(target, id, opts) when is_binary(id) and is_list(opts) do
    with_context(target, %{}, opts, fn context ->
      Store.fetch(context.store_mod, {context.namespace, id}, context.store_opts)
    end)
  end

  def get(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def retrieve(target, %Query{} = query, opts) when is_list(opts) do
    with_context(target, %{namespace: query.namespace}, opts, fn context ->
      with {:ok, effective_query} <- attach_namespace(query, context.namespace),
           {:ok, records} <- context.store_mod.query(effective_query, context.store_opts) do
        {:ok, build_retrieve_result(records, effective_query, context)}
      end
    end)
  end

  def retrieve(target, query_attrs, opts) when is_list(query_attrs) and is_list(opts),
    do: retrieve(target, Map.new(query_attrs), opts)

  def retrieve(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with_context(target, query_attrs, opts, fn context ->
      with {:ok, query} <- build_query(query_attrs, context.namespace),
           {:ok, records} <- context.store_mod.query(query, context.store_opts) do
        {:ok, build_retrieve_result(records, query, context)}
      end
    end)
  end

  def retrieve(_target, _query, _opts), do: {:error, :invalid_query}

  @impl true
  def forget(target, id, opts) when is_binary(id) and is_list(opts) do
    with_context(target, %{}, opts, fn context ->
      case context.store_mod.get({context.namespace, id}, context.store_opts) do
        {:ok, _record} ->
          :ok = context.store_mod.delete({context.namespace, id}, context.store_opts)
          {:ok, true}

        :not_found ->
          {:ok, false}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  def forget(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def prune(target, opts) when is_list(opts) do
    with_context(target, %{}, opts, fn context ->
      context.store_mod.prune_expired(context.store_opts)
    end)
  end

  def prune(_target, _opts), do: {:error, :invalid_opts}

  @impl true
  def ingest(target, request, opts) when is_list(opts) do
    with {:ok, {normalized_request, context}} <- normalize_ingest_request(target, request, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, stored_records} <- store_ingest_records(normalized_request.records, context) do
      {:ok, build_ingest_result(stored_records, context)}
    end
  end

  @impl true
  def explain_retrieval(target, query, opts) when is_list(opts) do
    with {:ok, %RetrieveResult{} = result} <- retrieve(target, query, opts) do
      summary = "#{result.total_count} hit(s) returned by basic provider"

      {:ok,
       Explanation.new!(%{
         query: result.query,
         scope: result.scope,
         provider: result.provider,
         summary: summary,
         reasons:
           Enum.map(result.hits, fn hit ->
             %{
               id: hit.record.id,
               matched_on: hit.matched_on,
               score: hit.score,
               rank: hit.rank
             }
           end),
         metadata: %{hit_count: result.total_count}
       })}
    end
  end

  @impl true
  def consolidate(target, opts) when is_list(opts) do
    with_context(target, %{}, opts, fn context ->
      with {:ok, pruned_count} <- context.store_mod.prune_expired(context.store_opts) do
        {:ok, build_consolidation_result(pruned_count, context)}
      end
    end)
  end

  @impl true
  @spec child_specs(keyword()) :: [Supervisor.child_spec()]
  def child_specs(_opts), do: []

  defp normalize_ingest_request(target, %IngestRequest{} = request, opts) do
    with {:ok, context} <- resolve_context(target, ingest_context_attrs(request), opts),
         adjusted_records <- apply_scope_namespace(request.records, context.namespace) do
      request
      |> rebuild_ingest_request(adjusted_records, context)
      |> wrap_ingest_request(context)
    end
  end

  defp normalize_ingest_request(target, attrs, opts) when is_list(attrs),
    do: normalize_ingest_request(target, Map.new(attrs), opts)

  defp normalize_ingest_request(target, %{} = attrs, opts) do
    context_attrs = ingest_context_attrs(attrs)

    with {:ok, context} <- resolve_context(target, context_attrs, opts),
         adjusted_records <-
           apply_scope_namespace(Helpers.map_get(attrs, :records, []), context.namespace) do
      attrs
      |> Map.put(:records, adjusted_records)
      |> Map.put_new(:scope, build_scope(context))
      |> wrap_ingest_request(context)
    end
  end

  defp normalize_ingest_request(_target, _request, _opts), do: {:error, :invalid_ingest_request}

  defp ingest_context_attrs(%IngestRequest{scope: %Scope{namespace: namespace}, records: records}),
    do: ingest_context_attrs(%{scope: %{namespace: namespace}, records: records})

  defp ingest_context_attrs(%IngestRequest{records: records}) do
    ingest_context_attrs(%{records: records})
  end

  defp ingest_context_attrs(%{} = attrs) do
    namespace =
      attrs
      |> Helpers.map_get(:scope, %{})
      |> case do
        %Scope{namespace: scope_namespace} -> scope_namespace
        %{} = scope_map -> Helpers.map_get(scope_map, :namespace)
        _ -> nil
      end

    record_namespace =
      attrs
      |> Helpers.map_get(:records, [])
      |> List.wrap()
      |> Enum.find_value(fn
        %Record{namespace: record_namespace} -> record_namespace
        %{} = record_attrs -> Helpers.map_get(record_attrs, :namespace)
        _ -> nil
      end)

    %{namespace: namespace || record_namespace}
  end

  defp apply_scope_namespace(records, namespace) when is_list(records) and is_binary(namespace) do
    Enum.map(records, fn
      %Record{namespace: existing} = record when is_binary(existing) and existing != "" ->
        record

      %Record{} = record ->
        %{record | namespace: namespace}

      %{} = record_attrs ->
        Map.put_new(record_attrs, :namespace, namespace)

      other ->
        other
    end)
  end

  defp apply_scope_namespace(records, _namespace), do: List.wrap(records)

  defp store_ingest_records(records, context) do
    records
    |> Enum.reduce_while({:ok, []}, fn
      %Record{} = record, {:ok, acc} ->
        record = if record.namespace == nil, do: %{record | namespace: context.namespace}, else: record

        case context.store_mod.put(record, context.store_opts) do
          {:ok, stored} -> {:cont, {:ok, [stored | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      _other, _acc ->
        {:halt, {:error, :invalid_ingest_record}}
    end)
    |> case do
      {:ok, stored_records} -> {:ok, Enum.reverse(stored_records)}
      {:error, _reason} = error -> error
    end
  end

  defp build_record(attrs, namespace, now) do
    attrs =
      attrs
      |> Map.drop([:provider, "provider", :provider_opts, "provider_opts"])
      |> Map.put(:namespace, namespace)
      |> Map.put_new(:observed_at, now)

    Record.new(attrs, now: now)
  end

  defp build_query(attrs, namespace) do
    attrs =
      attrs
      |> Map.drop([:provider, "provider", :provider_opts, "provider_opts"])
      |> put_default_namespace(namespace)

    Query.new(attrs)
  end

  defp build_retrieve_result(records, query, context) do
    RetrieveResult.from_records(records,
      query: query,
      scope: build_scope(context),
      provider: info_struct(context.provider_opts),
      metadata: %{store: context.store_mod}
    )
  end

  defp build_ingest_result(stored_records, context) do
    IngestResult.new!(%{
      accepted_count: length(stored_records),
      records: stored_records,
      scope: build_scope(context),
      provider: info_struct(context.provider_opts),
      metadata: %{}
    })
  end

  defp build_consolidation_result(pruned_count, context) do
    ConsolidationResult.new!(%{
      scope: build_scope(context),
      provider: info_struct(context.provider_opts),
      status: :ok,
      consolidated_count: 0,
      pruned_count: pruned_count,
      metadata: %{}
    })
  end

  defp put_default_namespace(attrs, namespace) when is_binary(namespace) do
    value = Helpers.map_get(attrs, :namespace)

    if missing_namespace?(value) do
      Map.put(attrs, :namespace, namespace)
    else
      attrs
    end
  end

  defp put_default_namespace(attrs, _namespace), do: attrs

  defp missing_namespace?(nil), do: true
  defp missing_namespace?(""), do: true
  defp missing_namespace?(value) when is_binary(value), do: String.trim(value) == ""
  defp missing_namespace?(_value), do: false

  defp attach_namespace(%Query{namespace: nil} = query, namespace) when is_binary(namespace),
    do: {:ok, %{query | namespace: namespace}}

  defp attach_namespace(%Query{namespace: query_namespace} = query, runtime_namespace)
       when is_binary(query_namespace) and is_binary(runtime_namespace),
       do: {:ok, query}

  defp attach_namespace(%Query{}, _), do: {:error, :namespace_required}

  defp resolve_context(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    plugin_state = Helpers.plugin_state(target, Jido.Memory.Runtime.plugin_state_key())
    now = Keyword.get(opts, :now, System.system_time(:millisecond))

    with {:ok, namespace} <- resolve_namespace(target, attrs, opts, plugin_state),
         {:ok, {store_mod, store_opts}} <- resolve_store(attrs, opts, plugin_state) do
      {:ok,
       %{
         namespace: namespace,
         store_mod: store_mod,
         store_opts: store_opts,
         provider_opts: opts,
         now: now
       }}
    end
  end

  defp resolve_namespace(target, attrs, opts, plugin_state) do
    resolved =
      Helpers.normalize_optional_string(Helpers.pick_value(opts, attrs, :namespace)) ||
        Helpers.normalize_optional_string(Helpers.map_get(plugin_state, :namespace)) ||
        case Helpers.target_id(target) do
          id when is_binary(id) -> "agent:" <> id
          _ -> nil
        end

    if is_binary(resolved), do: {:ok, resolved}, else: {:error, :namespace_required}
  end

  defp resolve_store(attrs, opts, plugin_state) do
    explicit_store = Helpers.pick_value(opts, attrs, :store)
    explicit_store_opts = Helpers.pick_value(opts, attrs, :store_opts, [])
    plugin_store = Helpers.map_get(plugin_state, :store)

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
         {:ok, merged_opts} <- merge_store_opts(base_opts, explicit_store_opts) do
      {:ok, {store_mod, merged_opts}}
    end
  end

  defp merge_store_opts(base_opts, explicit_store_opts)
       when is_list(base_opts) and is_list(explicit_store_opts) do
    with :ok <- validate_store_opts_shape(base_opts),
         :ok <- validate_store_opts_shape(explicit_store_opts) do
      {:ok, Keyword.merge(base_opts, explicit_store_opts)}
    end
  end

  defp merge_store_opts(_base, _explicit_opts), do: {:error, :invalid_store_opts}

  defp validate_store_opts_shape(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, :invalid_store_opts}
  end

  defp validate_store_opts_for_store(store_mod, base_opts, store_opts) do
    with :ok <- validate_store_opts_shape(base_opts),
         :ok <- validate_store_opts_shape(store_opts) do
      Store.validate_options(store_mod, Keyword.merge(base_opts, store_opts))
    end
  end

  defp rebuild_ingest_request(%IngestRequest{} = request, records, context) do
    %{
      records: records,
      scope: request.scope || build_scope(context),
      metadata: request.metadata,
      extensions: request.extensions
    }
  end

  defp wrap_ingest_request(attrs, context) do
    case IngestRequest.new(attrs) do
      {:ok, request} -> {:ok, {request, context}}
      {:error, _reason} = error -> error
    end
  end

  defp with_context(target, attrs, opts, fun) when is_map(attrs) and is_list(opts) and is_function(fun, 1) do
    with {:ok, context} <- resolve_context(target, attrs, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts) do
      fun.(context)
    end
  end

  defp build_scope(context) do
    Scope.new!(%{
      namespace: context.namespace,
      provider: __MODULE__,
      metadata: %{
        store: context.store_mod,
        store_opts: context.store_opts,
        provider_opts: context.provider_opts
      }
    })
  end

  defp info_struct(provider_opts) do
    {:ok, %ProviderInfo{} = info} = info(provider_opts, :all)
    info
  end

  defp version do
    case Application.spec(:jido_memory, :vsn) do
      nil -> nil
      value when is_list(value) -> to_string(value)
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp validate_namespace(nil), do: :ok
  defp validate_namespace(namespace) when is_binary(namespace), do: :ok
  defp validate_namespace(_), do: {:error, :invalid_namespace}

  defp validate_provider_opts_shape(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, :invalid_provider_opts}
  end

  defp validate_store(nil, _store_opts), do: :ok

  defp validate_store(store, store_opts) when is_list(store_opts) do
    case Store.normalize_store(store) do
      {:ok, {store_mod, base_opts}} ->
        validate_store_opts_for_store(store_mod, base_opts, store_opts)

      {:error, _reason} ->
        {:error, :invalid_store}
    end
  end

  defp validate_store(_store, _store_opts), do: {:error, :invalid_store_opts}
end
