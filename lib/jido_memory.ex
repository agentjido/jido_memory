defmodule Jido.Memory.Runtime do
  @moduledoc """
  Facade API for writing and retrieving memory records.

  Works with either:
  - agent/context inputs that already carry memory plugin state, or
  - explicit `namespace` and optional `provider` options for non-plugin callers.
  """

  alias Jido.Memory.{
    CapabilitySet,
    ConsolidationResult,
    Explanation,
    Helpers,
    IngestResult,
    ProviderInfo,
    ProviderRef,
    ProviderRegistry,
    Query,
    Record,
    RetrieveResult,
    Scope
  }

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
    with_provider(target, attrs, opts, fn provider_mod, provider_opts ->
      provider_mod.remember(target, attrs, provider_opts)
    end)
  end

  def remember(_target, _attrs, _opts), do: {:error, :invalid_attrs}

  @doc "Reads a single memory record by id."
  @spec get(target(), String.t(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def get(target, id, opts \\ [])

  def get(target, id, opts) when is_binary(id) and is_list(opts) do
    with_provider(target, %{}, opts, fn provider_mod, provider_opts ->
      provider_mod.get(target, id, provider_opts)
    end)
  end

  def get(_target, _id, _opts), do: {:error, :invalid_id}

  @doc "Deletes a memory record by id and returns whether it existed."
  @spec forget(target(), String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def forget(target, id, opts \\ [])

  def forget(target, id, opts) when is_binary(id) and is_list(opts) do
    with_provider(target, %{}, opts, fn provider_mod, provider_opts ->
      provider_mod.forget(target, id, provider_opts)
    end)
  end

  def forget(_target, _id, _opts), do: {:error, :invalid_id}

  @doc "Canonical retrieval entrypoint that delegates through provider."
  @spec retrieve(target(), Query.t() | map() | keyword(), keyword()) ::
          {:ok, RetrieveResult.t()} | {:error, term()}
  def retrieve(target, query_attrs, opts \\ [])

  def retrieve(target, query_attrs, opts) when is_list(query_attrs) and is_list(opts),
    do: retrieve(target, Map.new(query_attrs), opts)

  def retrieve(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with_provider(target, query_attrs, opts, fn provider_mod, provider_opts ->
      with {:ok, result} <- provider_mod.retrieve(target, query_attrs, provider_opts),
           {:ok, query} <- normalize_query(query_attrs) do
        normalize_retrieve_result(result, query, provider_mod, target, query_attrs, provider_opts)
      end
    end)
  end

  def retrieve(_target, _query, _opts), do: {:error, :invalid_query}

  @doc "Returns the canonical capability set for the active provider."
  @spec capabilities(target(), keyword()) :: {:ok, CapabilitySet.t()} | {:error, term()}
  def capabilities(target, opts \\ []) when is_list(opts) do
    with_provider(target, %{}, opts, fn provider_mod, provider_opts ->
      load_capability_set(provider_mod, provider_opts)
    end)
  end

  @doc "Returns canonical provider metadata."
  @spec info(target(), keyword()) :: {:ok, ProviderInfo.t()} | {:error, term()}
  def info(target, opts \\ []) when is_list(opts), do: info(target, opts, :all)

  @doc "Returns provider metadata, optionally filtered to selected fields."
  @spec info(target(), keyword(), :all | [atom()]) :: {:ok, ProviderInfo.t() | map()} | {:error, term()}
  def info(target, opts, fields) when is_list(opts) do
    with_provider(target, %{}, opts, fn provider_mod, provider_opts ->
      with {:ok, info} <- provider_mod.info(provider_opts, :all),
           {:ok, normalized} <- normalize_provider_info(info, provider_mod) do
        select_provider_info_fields(normalized, fields)
      end
    end)
  end

  @doc "Runs canonical ingestion when supported by the provider."
  @spec ingest(target(), map() | keyword(), keyword()) :: {:ok, IngestResult.t()} | {:error, term()}
  def ingest(target, request, opts \\ [])

  def ingest(target, request, opts) when is_list(request) and is_list(opts),
    do: ingest(target, Map.new(request), opts)

  def ingest(target, request, opts) when is_map(request) and is_list(opts) do
    with_provider_capability(target, request, opts, :ingest, :ingest, 3, fn provider_mod, provider_opts ->
      with {:ok, result} <- provider_mod.ingest(target, request, provider_opts) do
        normalize_ingest_result(result, provider_mod, target, request, provider_opts)
      end
    end)
  end

  def ingest(_target, _request, _opts), do: {:error, :invalid_ingest_request}

  @doc "Returns a canonical retrieval explanation when supported by the provider."
  @spec explain_retrieval(target(), Query.t() | map() | keyword(), keyword()) ::
          {:ok, Explanation.t()} | {:error, term()}
  def explain_retrieval(target, query_attrs, opts \\ [])

  def explain_retrieval(target, query_attrs, opts) when is_list(query_attrs) and is_list(opts),
    do: explain_retrieval(target, Map.new(query_attrs), opts)

  def explain_retrieval(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with_provider_capability(
      target,
      query_attrs,
      opts,
      :explain_retrieval,
      :explain_retrieval,
      3,
      fn provider_mod, provider_opts ->
        with {:ok, explanation} <- provider_mod.explain_retrieval(target, query_attrs, provider_opts) do
          normalize_explanation(explanation, provider_mod, target, query_attrs, provider_opts)
        end
      end
    )
  end

  def explain_retrieval(_target, _query, _opts), do: {:error, :invalid_query}

  @doc "Runs canonical lifecycle consolidation when supported by the provider."
  @spec consolidate(target(), keyword()) :: {:ok, ConsolidationResult.t()} | {:error, term()}
  def consolidate(target, opts \\ []) when is_list(opts) do
    with_provider_capability(target, %{}, opts, :consolidate, :consolidate, 2, fn provider_mod, provider_opts ->
      with {:ok, result} <- provider_mod.consolidate(target, provider_opts) do
        normalize_consolidation_result(result, provider_mod, target, provider_opts)
      end
    end)
  end

  @doc "Prunes expired records in the active store."
  @spec prune_expired(target(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def prune_expired(target, opts \\ []) when is_list(opts) do
    with_provider(target, %{}, opts, fn provider_mod, provider_opts ->
      provider_mod.prune(target, provider_opts)
    end)
  end

  @doc "Infers provider and provider options for plugin and action code paths."
  @spec resolve_provider(target(), map(), keyword()) ::
          {:ok, {module(), keyword()}} | {:error, term()}
  def resolve_provider(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    plugin_state = Helpers.plugin_state(target, @plugin_state_key)
    provider_input = Helpers.pick_value(opts, attrs, :provider)

    with {:ok, provider_ref} <- ProviderRef.normalize(provider_input),
         {:ok, provider_opts} <- merge_provider_opts(provider_ref, plugin_state, attrs, opts),
         {:ok, _module} <- ProviderRef.validate(%{provider_ref | opts: provider_opts}) do
      {:ok, {provider_ref.module, provider_opts}}
    end
  end

  @spec merge_provider_opts(ProviderRef.t(), map(), map(), keyword()) :: {:ok, keyword()} | {:error, term()}
  defp merge_provider_opts(%ProviderRef{module: provider_mod, opts: base_opts}, plugin_state, attrs, opts)
       when is_list(base_opts) and is_map(plugin_state) and is_map(attrs) and is_list(opts) do
    plugin_state_opts = provider_defaults_from_plugin_state(plugin_state, provider_mod)
    attr_defaults = provider_defaults_from_map(attrs, provider_mod)
    attr_opts = Helpers.map_get(attrs, :provider_opts, [])
    runtime_defaults = provider_defaults_from_opts(opts, provider_mod)
    runtime_opts = Keyword.get(opts, :provider_opts, [])

    with :ok <- validate_provider_opts_input(plugin_state_opts),
         :ok <- validate_provider_opts_input(attr_defaults),
         :ok <- validate_provider_opts_input(attr_opts),
         :ok <- validate_provider_opts_input(runtime_defaults),
         :ok <- validate_provider_opts_input(runtime_opts) do
      merged_opts = Keyword.merge(base_opts, plugin_state_opts)
      merged_opts = Keyword.merge(merged_opts, attr_defaults)
      merged_opts = Keyword.merge(merged_opts, attr_opts)
      merged_opts = Keyword.merge(merged_opts, runtime_defaults)
      merged_opts = Keyword.merge(merged_opts, runtime_opts)

      {:ok, merged_opts}
    end
  end

  defp normalize_retrieve_result(%RetrieveResult{} = result, query, provider_mod, target, attrs, provider_opts) do
    {:ok, merge_retrieve_defaults(result, query, provider_mod, target, attrs, provider_opts)}
  end

  defp normalize_retrieve_result(records, query, provider_mod, target, attrs, provider_opts) when is_list(records) do
    {:ok,
     RetrieveResult.from_records(records,
       query: query,
       scope: infer_scope(target, attrs, provider_mod, provider_opts),
       provider: infer_provider_info(provider_mod, provider_opts)
     )}
  end

  defp normalize_retrieve_result(%{} = attrs, query, provider_mod, target, query_attrs, provider_opts) do
    with {:ok, result} <- RetrieveResult.new(attrs) do
      {:ok, merge_retrieve_defaults(result, query, provider_mod, target, query_attrs, provider_opts)}
    end
  end

  defp normalize_retrieve_result(other, _query, _provider_mod, _target, _attrs, _opts),
    do: {:error, {:invalid_retrieve_result, other}}

  defp merge_retrieve_defaults(%RetrieveResult{} = result, query, provider_mod, target, attrs, provider_opts) do
    default_scope = infer_scope(target, attrs, provider_mod, provider_opts)
    default_provider = infer_provider_info(provider_mod, provider_opts)

    %RetrieveResult{
      result
      | query: result.query || query,
        scope: result.scope || default_scope,
        provider: result.provider || default_provider,
        total_count:
          if(result.total_count == 0 and result.hits != [], do: length(result.hits), else: result.total_count)
    }
  end

  defp normalize_capability_set(%CapabilitySet{} = capabilities, provider_mod) do
    capabilities
    |> Map.from_struct()
    |> Map.put_new(:provider, provider_mod)
    |> Map.put_new(:key, ProviderRegistry.key_for(provider_mod))
    |> CapabilitySet.new()
  end

  defp normalize_capability_set(%{} = attrs, provider_mod) do
    attrs
    |> Map.put_new(:provider, provider_mod)
    |> Map.put_new(:key, ProviderRegistry.key_for(provider_mod))
    |> CapabilitySet.new()
  end

  defp normalize_capability_set(values, provider_mod) when is_list(values) do
    CapabilitySet.new(%{
      provider: provider_mod,
      key: ProviderRegistry.key_for(provider_mod),
      capabilities: values
    })
  end

  defp normalize_capability_set(other, _provider_mod), do: {:error, {:invalid_capability_set, other}}

  defp normalize_provider_info(%ProviderInfo{} = info, provider_mod) do
    info
    |> Map.from_struct()
    |> Map.put_new(:provider, provider_mod)
    |> Map.put_new(:key, ProviderRegistry.key_for(provider_mod))
    |> ProviderInfo.new()
  end

  defp normalize_provider_info(%{} = attrs, provider_mod) do
    attrs
    |> Map.put_new(:provider, provider_mod)
    |> Map.put_new(:key, ProviderRegistry.key_for(provider_mod))
    |> ProviderInfo.new()
  end

  defp normalize_provider_info(other, _provider_mod), do: {:error, {:invalid_provider_info, other}}

  defp select_provider_info_fields(%ProviderInfo{} = info, :all), do: {:ok, info}

  defp select_provider_info_fields(%ProviderInfo{} = info, values) when is_list(values) do
    {:ok, Map.take(Map.from_struct(info), values)}
  end

  defp normalize_ingest_result(%IngestResult{} = result, provider_mod, _target, request, provider_opts) do
    {:ok, merge_ingest_defaults(result, provider_mod, request, provider_opts)}
  end

  defp normalize_ingest_result(%{} = attrs, provider_mod, _target, request, provider_opts) do
    with {:ok, result} <- IngestResult.new(attrs) do
      {:ok, merge_ingest_defaults(result, provider_mod, request, provider_opts)}
    end
  end

  defp normalize_ingest_result(other, _provider_mod, _target, _request, _opts),
    do: {:error, {:invalid_ingest_result, other}}

  defp merge_ingest_defaults(%IngestResult{} = result, provider_mod, request, provider_opts) do
    %IngestResult{
      result
      | scope: result.scope || infer_scope_from_request(request, provider_mod, provider_opts),
        provider: result.provider || infer_provider_info(provider_mod, provider_opts)
    }
  end

  defp normalize_explanation(%Explanation{} = explanation, provider_mod, target, query, provider_opts) do
    {:ok, merge_explanation_defaults(explanation, provider_mod, target, query, provider_opts)}
  end

  defp normalize_explanation(%{} = attrs, provider_mod, target, query, provider_opts) do
    with {:ok, explanation} <- Explanation.new(attrs) do
      {:ok, merge_explanation_defaults(explanation, provider_mod, target, query, provider_opts)}
    end
  end

  defp normalize_explanation(other, _provider_mod, _target, _query, _opts),
    do: {:error, {:invalid_explanation, other}}

  defp merge_explanation_defaults(%Explanation{} = explanation, provider_mod, target, query, provider_opts) do
    %Explanation{
      explanation
      | query: explanation.query || normalize_query!(query),
        scope: explanation.scope || infer_scope(target, query, provider_mod, provider_opts),
        provider: explanation.provider || infer_provider_info(provider_mod, provider_opts)
    }
  end

  defp normalize_consolidation_result(%ConsolidationResult{} = result, provider_mod, target, provider_opts) do
    {:ok, merge_consolidation_defaults(result, provider_mod, target, provider_opts)}
  end

  defp normalize_consolidation_result(%{} = attrs, provider_mod, target, provider_opts) do
    with {:ok, result} <- ConsolidationResult.new(attrs) do
      {:ok, merge_consolidation_defaults(result, provider_mod, target, provider_opts)}
    end
  end

  defp normalize_consolidation_result(other, _provider_mod, _target, _opts),
    do: {:error, {:invalid_consolidation_result, other}}

  defp merge_consolidation_defaults(%ConsolidationResult{} = result, provider_mod, target, provider_opts) do
    %ConsolidationResult{
      result
      | scope: result.scope || infer_scope(target, %{}, provider_mod, provider_opts),
        provider: result.provider || infer_provider_info(provider_mod, provider_opts)
    }
  end

  defp load_capability_set(provider_mod, provider_opts) do
    case provider_mod.capabilities(provider_opts) do
      {:ok, capability_set} -> normalize_capability_set(capability_set, provider_mod)
      other -> other
    end
  end

  defp ensure_capability(provider_mod, provider_opts, callback, arity, capability) do
    with {:ok, capability_set} <- load_capability_set(provider_mod, provider_opts) do
      cond do
        not CapabilitySet.supports?(capability_set, capability) ->
          {:error, {:unsupported_capability, capability, provider_mod}}

        function_exported?(provider_mod, callback, arity) ->
          :ok

        true ->
          {:error, {:invalid_provider_capability, capability, provider_mod}}
      end
    end
  end

  defp infer_provider_info(provider_mod, provider_opts) do
    case provider_mod.info(provider_opts, :all) do
      {:ok, info} ->
        case normalize_provider_info(info, provider_mod) do
          {:ok, %ProviderInfo{} = normalized} -> normalized
          {:error, _reason} -> default_provider_info(provider_mod)
        end

      {:error, _reason} ->
        default_provider_info(provider_mod)
    end
  end

  defp default_provider_info(provider_mod) do
    ProviderInfo.new!(%{
      name: Scope.provider_name(provider_mod) || "provider",
      key: ProviderRegistry.key_for(provider_mod),
      provider: provider_mod,
      capabilities: []
    })
  end

  defp infer_scope(target, attrs, provider_mod, provider_opts) do
    namespace =
      Helpers.pick_value(
        provider_opts,
        attrs,
        :namespace,
        Helpers.map_get(Helpers.plugin_state(target, @plugin_state_key), :namespace)
      )

    provider_opts = maybe_put(provider_opts, :namespace, namespace)

    Scope.from_provider(provider_mod, provider_opts)
  end

  defp infer_scope_from_request(request, provider_mod, provider_opts) when is_map(request) do
    scope = Helpers.map_get(request, :scope)

    case scope do
      %Scope{} = scope ->
        scope

      %{} = scope_map ->
        Scope.new!(scope_map)

      _ ->
        records = Helpers.map_get(request, :records, [])

        namespace =
          records
          |> List.wrap()
          |> Enum.find_value(fn
            %Record{namespace: namespace} -> namespace
            %{} = attrs -> Helpers.map_get(attrs, :namespace)
            _ -> nil
          end)

        Scope.from_provider(provider_mod, maybe_put(provider_opts, :namespace, namespace))
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put_new(opts, key, value)

  defp with_provider(target, attrs, opts, fun) when is_map(attrs) and is_list(opts) and is_function(fun, 2) do
    with {:ok, {provider_mod, provider_opts}} <- resolve_provider(target, attrs, opts),
         :ok <- provider_mod.validate_config(provider_opts) do
      fun.(provider_mod, provider_opts)
    end
  end

  defp with_provider_capability(target, attrs, opts, capability, callback, arity, fun)
       when is_map(attrs) and is_list(opts) and is_function(fun, 2) do
    with_provider(target, attrs, opts, fn provider_mod, provider_opts ->
      with :ok <- ensure_capability(provider_mod, provider_opts, callback, arity, capability) do
        fun.(provider_mod, provider_opts)
      end
    end)
  end

  defp normalize_query(%Query{} = query), do: {:ok, query}
  defp normalize_query(query_attrs) when is_map(query_attrs), do: Query.new(query_attrs)

  defp normalize_query!(query_attrs) do
    case normalize_query(query_attrs) do
      {:ok, query} -> query
      {:error, _reason} -> Query.new!(%{})
    end
  end

  defp validate_provider_opts_input(opts) when is_list(opts), do: :ok
  defp validate_provider_opts_input(_), do: {:error, :invalid_provider_opts}

  defp provider_defaults_from_plugin_state(plugin_state, provider_mod) when is_map(plugin_state) do
    []
    |> maybe_put_provider_opt(:namespace, Helpers.normalize_optional_string(Helpers.map_get(plugin_state, :namespace)))
    |> maybe_put_provider_store_defaults(provider_mod, plugin_state)
  end

  defp provider_defaults_from_map(attrs, provider_mod) when is_map(attrs) do
    []
    |> maybe_put_provider_opt(:namespace, Helpers.normalize_optional_string(Helpers.map_get(attrs, :namespace)))
    |> maybe_put_provider_store_default(provider_mod, :store, Helpers.map_get(attrs, :store))
    |> maybe_put_provider_store_default(
      provider_mod,
      :store_opts,
      normalize_provider_store_opts(Helpers.map_get(attrs, :store_opts))
    )
  end

  defp provider_defaults_from_opts(opts, provider_mod) when is_list(opts) do
    []
    |> maybe_put_provider_opt(:namespace, Helpers.normalize_optional_string(Keyword.get(opts, :namespace)))
    |> maybe_put_provider_store_default(provider_mod, :store, Keyword.get(opts, :store))
    |> maybe_put_provider_store_default(
      provider_mod,
      :store_opts,
      normalize_provider_store_opts(Keyword.get(opts, :store_opts))
    )
  end

  defp maybe_put_provider_opt(opts, _key, nil), do: opts
  defp maybe_put_provider_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_provider_store_defaults(opts, provider_mod, plugin_state) do
    opts
    |> maybe_put_provider_store_default(provider_mod, :store, Helpers.map_get(plugin_state, :store))
  end

  defp maybe_put_provider_store_default(opts, provider_mod, key, value) do
    if store_backed_provider?(provider_mod) do
      maybe_put_provider_opt(opts, key, value)
    else
      opts
    end
  end

  defp store_backed_provider?(Jido.Memory.Provider.Basic), do: true
  defp store_backed_provider?(Jido.Memory.Provider.Redis), do: true
  defp store_backed_provider?(_provider_mod), do: false

  defp normalize_provider_store_opts(nil), do: nil
  defp normalize_provider_store_opts(opts) when is_list(opts), do: opts
  defp normalize_provider_store_opts(opts), do: opts
end
