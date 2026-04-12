defmodule Jido.Memory.Provider.Redis do
  @moduledoc """
  Built-in Redis provider for the canonical store-backed memory path.
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
    IngestResult,
    ProviderInfo,
    Query,
    RetrieveResult,
    Scope,
    Store
  }

  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Store.Redis, as: RedisStore

  @default_store {RedisStore, []}
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

  @doc "Returns the provider schema."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @impl true
  def validate_config(opts) when is_list(opts) do
    namespace = Keyword.get(opts, :namespace)
    store = Keyword.get(opts, :store)
    store_opts = Keyword.get(opts, :store_opts, [])

    with :ok <- validate_namespace(namespace),
         true <- is_list(store_opts),
         :ok <- validate_store_config(store, store_opts) do
      :ok
    else
      false -> {:error, :invalid_store_opts}
      {:error, _reason} = error -> error
    end
  end

  def validate_config(_opts), do: {:error, :invalid_provider_opts}

  @impl true
  def capabilities(opts) when is_list(opts) do
    with {:ok, merged_opts} <- merge_default_store(opts) do
      {:ok,
       CapabilitySet.new!(%{
         key: :redis,
         provider: __MODULE__,
         capabilities: @capabilities,
         descriptor: @capability_descriptor,
         metadata: %{provider_opts: merged_opts}
       })}
    end
  end

  def capabilities(_opts), do: {:error, :invalid_provider_opts}

  @impl true
  def info(opts, _fields) when is_list(opts) do
    with {:ok, merged_opts} <- merge_default_store(opts) do
      {:ok,
       ProviderInfo.new!(%{
         name: "redis",
         key: :redis,
         provider: __MODULE__,
         provider_style: :redis,
         version: version(),
         description: "Provider that persists canonical records through Jido.Memory.Store.Redis",
         capabilities: @capabilities,
         capability_descriptor: @capability_descriptor,
         scope: Scope.from_provider(__MODULE__, merged_opts),
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
           provider_direct: []
         },
         defaults: %{
           namespace: Keyword.get(merged_opts, :namespace),
           store: Keyword.get(merged_opts, :store, @default_store),
           store_opts: Keyword.get(merged_opts, :store_opts, [])
         },
         metadata: %{store: Keyword.get(merged_opts, :store, @default_store)}
       })}
    end
  end

  def info(_opts, _fields), do: {:error, :invalid_provider_opts}

  @impl true
  def remember(target, attrs, opts) when is_list(attrs),
    do: remember(target, Map.new(attrs), opts)

  def remember(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    with {:ok, merged_opts} <- merge_default_store(opts) do
      Basic.remember(target, attrs, merged_opts)
    end
  end

  def remember(_target, _attrs, _opts), do: {:error, :invalid_attrs}

  @impl true
  def get(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, merged_opts} <- merge_default_store(opts) do
      Basic.get(target, id, merged_opts)
    end
  end

  def get(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def retrieve(target, %Query{} = query, opts) when is_list(opts) do
    with {:ok, merged_opts} <- merge_default_store(opts),
         {:ok, %RetrieveResult{} = result} <- Basic.retrieve(target, query, merged_opts) do
      {:ok, normalize_retrieve_result(result, merged_opts)}
    end
  end

  def retrieve(target, query_attrs, opts) when is_list(query_attrs) and is_list(opts),
    do: retrieve(target, Map.new(query_attrs), opts)

  def retrieve(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with {:ok, merged_opts} <- merge_default_store(opts),
         {:ok, %RetrieveResult{} = result} <- Basic.retrieve(target, query_attrs, merged_opts) do
      {:ok, normalize_retrieve_result(result, merged_opts)}
    end
  end

  def retrieve(_target, _query, _opts), do: {:error, :invalid_query}

  @impl true
  def forget(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, merged_opts} <- merge_default_store(opts) do
      Basic.forget(target, id, merged_opts)
    end
  end

  def forget(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def prune(target, opts) when is_list(opts) do
    with {:ok, merged_opts} <- merge_default_store(opts) do
      Basic.prune(target, merged_opts)
    end
  end

  def prune(_target, _opts), do: {:error, :invalid_opts}

  @impl true
  def ingest(target, request, opts) when is_list(opts) do
    with {:ok, merged_opts} <- merge_default_store(opts),
         {:ok, %IngestResult{} = result} <- Basic.ingest(target, request, merged_opts) do
      {:ok, normalize_ingest_result(result, merged_opts)}
    end
  end

  def ingest(_target, _request, _opts), do: {:error, :invalid_ingest_request}

  @impl true
  def explain_retrieval(target, query, opts) when is_list(opts) do
    with {:ok, %RetrieveResult{} = result} <- retrieve(target, query, opts) do
      summary = "#{result.total_count} hit(s) returned by redis provider"

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
    with {:ok, merged_opts} <- merge_default_store(opts),
         {:ok, %ConsolidationResult{} = result} <- Basic.consolidate(target, merged_opts) do
      {:ok, normalize_consolidation_result(result, merged_opts)}
    end
  end

  def consolidate(_target, _opts), do: {:error, :invalid_opts}

  @impl true
  @spec child_specs(keyword()) :: [Supervisor.child_spec()]
  def child_specs(_opts), do: []

  defp normalize_retrieve_result(%RetrieveResult{} = result, provider_opts) do
    %RetrieveResult{
      result
      | scope: normalize_scope(result.scope, provider_opts),
        provider: info_struct(provider_opts)
    }
  end

  defp normalize_ingest_result(%IngestResult{} = result, provider_opts) do
    %IngestResult{
      result
      | scope: normalize_scope(result.scope, provider_opts),
        provider: info_struct(provider_opts)
    }
  end

  defp normalize_consolidation_result(%ConsolidationResult{} = result, provider_opts) do
    %ConsolidationResult{
      result
      | scope: normalize_scope(result.scope, provider_opts),
        provider: info_struct(provider_opts)
    }
  end

  defp normalize_scope(%Scope{} = scope, _provider_opts) do
    Scope.new!(%{
      namespace: scope.namespace,
      provider: __MODULE__,
      metadata: scope.metadata
    })
  end

  defp normalize_scope(nil, provider_opts), do: Scope.from_provider(__MODULE__, provider_opts)

  defp info_struct(provider_opts) do
    case info(provider_opts, :all) do
      {:ok, %ProviderInfo{} = info} ->
        info

      _ ->
        ProviderInfo.new!(%{
          name: "redis",
          key: :redis,
          provider: __MODULE__,
          provider_style: :redis,
          capabilities: @capabilities,
          capability_descriptor: @capability_descriptor
        })
    end
  end

  defp merge_default_store(opts) when is_list(opts) do
    store = Keyword.get(opts, :store, @default_store)
    store_opts = Keyword.get(opts, :store_opts, [])

    with true <- is_list(store_opts),
         {:ok, validated_store} <- validate_store(store, store_opts) do
      {:ok, Keyword.put(opts, :store, validated_store)}
    else
      false -> {:error, :invalid_store_opts}
      {:error, _reason} = error -> error
    end
  end

  defp validate_store(store, store_opts) when is_list(store_opts) do
    case Store.normalize_store(store) do
      {:ok, {RedisStore, base_opts}} ->
        merged_opts = Keyword.merge(base_opts, store_opts)

        with :ok <- Store.validate_options(RedisStore, merged_opts) do
          {:ok, {RedisStore, base_opts}}
        end

      {:ok, _other} ->
        {:error, :invalid_store}

      {:error, _reason} ->
        {:error, :invalid_store}
    end
  end

  defp validate_store(_store, _store_opts), do: {:error, :invalid_store_opts}

  defp validate_store_config(nil, []), do: :ok

  defp validate_store_config(nil, store_opts) when is_list(store_opts) do
    Store.validate_options(RedisStore, store_opts)
  end

  defp validate_store_config(store, store_opts) when is_list(store_opts),
    do: validate_store(store, store_opts)

  defp validate_store_config(_store, _store_opts), do: {:error, :invalid_store_opts}

  defp validate_namespace(nil), do: :ok
  defp validate_namespace(namespace) when is_binary(namespace), do: :ok
  defp validate_namespace(_), do: {:error, :invalid_namespace}

  defp version do
    case Application.spec(:jido_memory, :vsn) do
      nil -> nil
      value when is_list(value) -> to_string(value)
      value when is_binary(value) -> value
      _ -> nil
    end
  end
end
