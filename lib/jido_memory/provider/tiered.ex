defmodule Jido.Memory.Provider.Tiered do
  @moduledoc """
  Built-in provider with short, mid, and long memory tiers.

  Short and mid tiers use the standard `Jido.Memory.Store` substrate. The long
  tier is routed through a pluggable `Jido.Memory.LongTermStore` backend so the
  provider can keep long-term persistence configurable without changing the
  common Jido memory facade.
  """

  @behaviour Jido.Memory.Provider
  @behaviour Jido.Memory.Capability.ExplainableRetrieval
  @behaviour Jido.Memory.Capability.Lifecycle

  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Query
  alias Jido.Memory.Record
  alias Jido.Memory.Store

  @default_short_store {Jido.Memory.Store.ETS, [table: :jido_memory_short]}
  @default_mid_store {Jido.Memory.Store.ETS, [table: :jido_memory_mid]}

  @default_long_term_store {Jido.Memory.LongTermStore.ETS, [store: {Jido.Memory.Store.ETS, [table: :jido_memory_long]}]}

  @default_lifecycle [
    short_to_mid_threshold: 0.65,
    mid_to_long_threshold: 0.85
  ]

  @capabilities %{
    core: true,
    retrieval: %{
      explainable: true,
      tiers: true,
      active: false,
      memory_types: false,
      provider_extensions: true,
      explanation_scope: :result_reasons
    },
    lifecycle: %{consolidate: true, promote: true, inspect: true},
    ingestion: %{batch: false, multimodal: false, routed: false, access: :none},
    operations: %{},
    governance: %{protected_memory: false, exact_preservation: false, access: :none},
    hooks: %{}
  }

  @required_long_term_callbacks [
    validate_config: 1,
    init: 1,
    remember: 3,
    get: 3,
    retrieve: 3,
    forget: 3,
    prune: 2,
    info: 2
  ]

  @type tier :: :short | :mid | :long

  @type context :: %{
          namespace: String.t(),
          now: integer(),
          short_store: {module(), keyword()},
          mid_store: {module(), keyword()},
          long_term_store: %{module: module(), opts: keyword(), meta: map()},
          lifecycle: keyword()
        }

  @impl true
  def validate_config(opts) when is_list(opts) do
    with :ok <- validate_namespace(Keyword.get(opts, :namespace)),
         {:ok, _short_store} <- normalize_store_pair(resolve_short_store_input(opts)),
         {:ok, _mid_store} <- normalize_store_pair(resolve_mid_store_input(opts)),
         {:ok, _long_term_store} <- normalize_long_term_store(resolve_long_term_input(opts)) do
      validate_lifecycle(Keyword.get(opts, :lifecycle, @default_lifecycle))
    end
  end

  def validate_config(_opts), do: {:error, :invalid_provider_opts}

  @impl true
  def child_specs(_opts), do: []

  @impl true
  def init(opts) do
    with :ok <- validate_config(opts),
         {:ok, short_store} <- normalize_store_pair(resolve_short_store_input(opts)),
         {:ok, mid_store} <- normalize_store_pair(resolve_mid_store_input(opts)),
         {:ok, long_term_store} <- normalize_long_term_store(resolve_long_term_input(opts)),
         :ok <- ensure_store_ready(short_store),
         :ok <- ensure_store_ready(mid_store),
         {:ok, long_term_meta} <- long_term_store.module.init(long_term_store.opts) do
      {:ok,
       %{
         provider: __MODULE__,
         defaults: %{
           namespace: normalize_optional_namespace(Keyword.get(opts, :namespace)),
           short_store: short_store,
           mid_store: mid_store,
           long_term_store: %{module: long_term_store.module, opts: long_term_store.opts}
         },
         lifecycle: normalize_lifecycle(Keyword.get(opts, :lifecycle, @default_lifecycle)),
         lifecycle_inspection: %{
           access: :provider_direct,
           payload_version: 1,
           summary_fields: [
             :provider,
             :namespace,
             :requested_tiers,
             :thresholds,
             :current_tiers,
             :recent_outcomes,
             :totals,
             :records
           ],
           record_fields: [
             :id,
             :tier,
             :decision,
             :source_tier,
             :destination_tier,
             :score,
             :threshold,
             :skip_reason,
             :promotion_count,
             :evaluation_count,
             :last_evaluated_at
           ]
         },
         explainability: %{
           payload_version: 1,
           canonical_fields: [
             :provider,
             :namespace,
             :query,
             :requested_tiers,
             :participating_tiers,
             :result_count,
             :results,
             :extensions
           ],
           result_fields: [:id, :tier, :rank, :matched_on, :ranking_context],
           extensions: [:tiered]
         },
         capabilities: @capabilities,
         long_term_meta: long_term_meta
       }}
    end
  end

  @impl true
  def capabilities(provider_meta), do: Map.get(provider_meta, :capabilities, @capabilities)

  @impl true
  def remember(target, attrs, opts) when is_list(attrs), do: remember(target, Map.new(attrs), opts)

  def remember(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    with {:ok, context} <- resolve_context(target, attrs, opts),
         {:ok, tier} <- resolve_single_tier(attrs, opts, :short) do
      write_record(target, attrs, context, tier)
    end
  end

  def remember(_target, _attrs, _opts), do: {:error, :invalid_attrs}

  @impl true
  def get(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{}, opts),
         {:ok, tiers} <- resolve_tiers(%{}, opts, default: :all) do
      fetch_record(target, id, context, tiers)
    end
  end

  def get(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def retrieve(target, %Query{} = query, opts) when is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{namespace: query.namespace}, opts),
         {:ok, tiers} <- resolve_tiers(query, opts, default: :all) do
      retrieve_records(target, query, context, tiers)
    end
  end

  def retrieve(target, query_attrs, opts) when is_list(query_attrs),
    do: retrieve(target, Map.new(query_attrs), opts)

  def retrieve(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with {:ok, base_query} <- build_query(query_attrs),
         {:ok, context} <- resolve_context(target, query_attrs, opts),
         {:ok, tiers} <- resolve_tiers(query_attrs, opts, default: :all) do
      retrieve_records(target, base_query, context, tiers)
    end
  end

  def retrieve(_target, _query, _opts), do: {:error, :invalid_query}

  @impl true
  def explain_retrieval(target, %Query{} = query, opts) when is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{namespace: query.namespace}, opts),
         {:ok, tiers} <- resolve_tiers(query, opts, default: :all),
         {:ok, bundles} <- do_retrieve_bundles(target, query, context, tiers) do
      {:ok, build_explanation(query, context, tiers, bundles)}
    end
  end

  def explain_retrieval(target, query_attrs, opts) when is_list(query_attrs),
    do: explain_retrieval(target, Map.new(query_attrs), opts)

  def explain_retrieval(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with {:ok, query} <- build_query(query_attrs),
         {:ok, context} <- resolve_context(target, query_attrs, opts),
         {:ok, tiers} <- resolve_tiers(query_attrs, opts, default: :all),
         {:ok, bundles} <- do_retrieve_bundles(target, query, context, tiers) do
      {:ok, build_explanation(query, context, tiers, bundles)}
    end
  end

  def explain_retrieval(_target, _query, _opts), do: {:error, :invalid_query}

  @impl true
  def forget(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{}, opts),
         {:ok, tiers} <- resolve_tiers(%{}, opts, default: :all) do
      delete_record(target, id, context, tiers)
    end
  end

  def forget(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def prune(target, opts) when is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{}, opts),
         {:ok, short_count} <- Basic.prune(target, namespace: context.namespace, store: context.short_store),
         {:ok, mid_count} <- Basic.prune(target, namespace: context.namespace, store: context.mid_store),
         {:ok, long_count} <- context.long_term_store.module.prune(target, long_term_runtime_opts(context, [])) do
      {:ok, short_count + mid_count + long_count}
    end
  end

  @impl true
  def info(provider_meta, :all), do: {:ok, provider_meta}

  def info(provider_meta, fields) when is_list(fields) do
    {:ok, Map.take(provider_meta, fields)}
  end

  def info(_provider_meta, _fields), do: {:error, :invalid_info_fields}

  @doc """
  Returns a provider-direct snapshot of Tiered lifecycle outcomes.

  This is intentionally provider-native rather than part of the common runtime
  facade so the shared API can stay narrow while Tiered grows richer inspection
  details.
  """
  @spec inspect_lifecycle(map() | struct(), keyword()) :: {:ok, map()} | {:error, term()}
  def inspect_lifecycle(target, opts \\ [])

  def inspect_lifecycle(target, opts) when is_list(opts) do
    with {:ok, normalized_opts} <- normalize_direct_opts(target, opts),
         {:ok, context} <- resolve_context(target, %{}, normalized_opts),
         {:ok, tiers} <- resolve_tiers(%{}, normalized_opts, default: :all),
         {:ok, query} <- Query.new(%{namespace: context.namespace, limit: 1_000, order: :desc}),
         {:ok, bundles} <- do_retrieve_bundles(target, query, context, tiers) do
      {:ok, build_lifecycle_snapshot(context, tiers, bundles)}
    end
  end

  def inspect_lifecycle(_target, _opts), do: {:error, :invalid_provider_opts}

  @impl true
  def consolidate(target, opts) when is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{}, opts),
         {:ok, requested_tiers} <- resolve_tiers(%{}, opts, default: :all),
         {:ok, short_result} <- maybe_promote_short(target, context, requested_tiers),
         {:ok, mid_result} <- maybe_promote_mid(target, context, requested_tiers) do
      {:ok,
       %{
         namespace: context.namespace,
         promoted_to_mid: short_result.promoted,
         promoted_to_long: mid_result.promoted,
         examined: %{short: short_result.examined, mid: mid_result.examined},
         thresholds: %{
           short_to_mid: Keyword.fetch!(context.lifecycle, :short_to_mid_threshold),
           mid_to_long: Keyword.fetch!(context.lifecycle, :mid_to_long_threshold)
         },
         tier_results: %{short: short_result, mid: mid_result}
       }}
    end
  end

  def consolidate(_target, _opts), do: {:error, :invalid_provider_opts}

  defp maybe_promote_short(target, context, tiers) do
    threshold = Keyword.fetch!(context.lifecycle, :short_to_mid_threshold)

    if :short in tiers do
      with {:ok, records} <-
             Basic.retrieve(target, %Query{namespace: context.namespace}, store: context.short_store) do
        promote_records(target, records, context, :short, :mid, threshold)
      end
    else
      {:ok, empty_promotion_result(:short, :mid, threshold)}
    end
  end

  defp maybe_promote_mid(target, context, tiers) do
    threshold = Keyword.fetch!(context.lifecycle, :mid_to_long_threshold)

    if :mid in tiers do
      with {:ok, records} <-
             Basic.retrieve(target, %Query{namespace: context.namespace}, store: context.mid_store) do
        promote_records(target, records, context, :mid, :long, threshold)
      end
    else
      {:ok, empty_promotion_result(:mid, :long, threshold)}
    end
  end

  defp promote_records(target, records, context, source_tier, destination_tier, threshold) do
    result =
      Enum.reduce(records, empty_promotion_result(source_tier, destination_tier, threshold), fn record, acc ->
        outcome = maybe_promote_record(record, target, context, source_tier, destination_tier, threshold)
        accumulate_promotion_outcome(acc, outcome)
      end)

    {:ok,
     %{
       result
       | examined: length(records),
         ids: Enum.reverse(result.ids),
         skipped_ids: Enum.reverse(result.skipped_ids),
         decisions: Enum.reverse(result.decisions)
     }}
  end

  defp maybe_promote_record(record, target, context, source_tier, destination_tier, threshold) do
    score = promotion_score(record)

    if score < threshold do
      skipped =
        lifecycle_evaluated_record(
          record,
          source_tier,
          destination_tier,
          score,
          threshold,
          :skipped,
          :below_threshold,
          context.now
        )

      persist_record(target, skipped, context, source_tier)

      promotion_outcome(record, :skipped, source_tier, destination_tier, score, threshold, :below_threshold)
    else
      promoted = promoted_record(record, source_tier, destination_tier, score, threshold, context.now)

      case write_record(target, Map.from_struct(promoted), context, destination_tier) do
        {:ok, _stored} ->
          :ok = delete_from_source(target, record, context)

          promotion_outcome(record, :promoted, source_tier, destination_tier, score, threshold)

        {:error, _reason} ->
          skipped =
            lifecycle_evaluated_record(
              record,
              source_tier,
              destination_tier,
              score,
              threshold,
              :skipped,
              :destination_write_failed,
              context.now
            )

          persist_record(target, skipped, context, source_tier)

          promotion_outcome(
            record,
            :skipped,
            source_tier,
            destination_tier,
            score,
            threshold,
            :destination_write_failed
          )
      end
    end
  end

  defp retrieve_records(target, %Query{} = query, context, tiers) do
    with {:ok, bundles} <- do_retrieve_bundles(target, query, context, tiers) do
      records =
        bundles
        |> Enum.flat_map(& &1.records)
        |> sort_records(query.order)
        |> Enum.uniq_by(& &1.id)
        |> Enum.take(query.limit)

      {:ok, records}
    end
  end

  defp do_retrieve_bundles(target, query, context, tiers) do
    tiers
    |> Enum.reduce_while({:ok, []}, fn tier, {:ok, acc} ->
      case retrieve_bundle_from_tier(target, query, context, tier) do
        {:ok, bundle} -> {:cont, {:ok, [bundle | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, bundles} -> {:ok, Enum.reverse(bundles)}
      {:error, _reason} = error -> error
    end
  end

  defp retrieve_bundle_from_tier(target, %Query{} = query, context, tier) do
    case retrieve_from_tier(target, query, context, tier) do
      {:ok, records} -> {:ok, %{tier: tier, records: records}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp retrieve_from_tier(target, %Query{} = query, context, :short) do
    Basic.retrieve(target, query, namespace: context.namespace, store: context.short_store)
  end

  defp retrieve_from_tier(target, %Query{} = query, context, :mid) do
    Basic.retrieve(target, query, namespace: context.namespace, store: context.mid_store)
  end

  defp retrieve_from_tier(target, %Query{} = query, context, :long) do
    context.long_term_store.module.retrieve(target, query, long_term_runtime_opts(context, []))
  end

  defp fetch_record(_target, _id, _context, []), do: {:error, :not_found}

  defp fetch_record(target, id, context, [tier | rest]) do
    case get_from_tier(target, id, context, tier) do
      {:ok, %Record{} = record} -> {:ok, record}
      {:error, :not_found} -> fetch_record(target, id, context, rest)
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_from_tier(target, id, context, :short) do
    Basic.get(target, id, namespace: context.namespace, store: context.short_store)
  end

  defp get_from_tier(target, id, context, :mid) do
    Basic.get(target, id, namespace: context.namespace, store: context.mid_store)
  end

  defp get_from_tier(target, id, context, :long) do
    context.long_term_store.module.get(target, id, long_term_runtime_opts(context, []))
  end

  defp delete_record(target, id, context, tiers) do
    tiers
    |> Enum.reduce_while({:ok, false}, fn tier, {:ok, deleted?} ->
      case forget_from_tier(target, id, context, tier) do
        {:ok, tier_deleted?} -> {:cont, {:ok, deleted? or tier_deleted?}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp forget_from_tier(target, id, context, :short) do
    Basic.forget(target, id, namespace: context.namespace, store: context.short_store)
  end

  defp forget_from_tier(target, id, context, :mid) do
    Basic.forget(target, id, namespace: context.namespace, store: context.mid_store)
  end

  defp forget_from_tier(target, id, context, :long) do
    context.long_term_store.module.forget(target, id, long_term_runtime_opts(context, []))
  end

  defp delete_from_source(target, %Record{} = record, context) do
    case tiered_metadata(record)[:tier] do
      :short -> Basic.forget(target, record.id, namespace: context.namespace, store: context.short_store)
      :mid -> Basic.forget(target, record.id, namespace: context.namespace, store: context.mid_store)
      :long -> context.long_term_store.module.forget(target, record.id, long_term_runtime_opts(context, []))
      _ -> {:ok, false}
    end
    |> case do
      {:ok, _deleted?} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp persist_record(target, %Record{} = record, context, tier) do
    case write_record(target, Map.from_struct(record), context, tier) do
      {:ok, _stored} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp write_record(target, attrs, context, tier) do
    decorated_attrs = decorate_attrs(attrs, tier, context.now)

    case tier do
      :short ->
        Basic.remember(target, decorated_attrs,
          namespace: context.namespace,
          store: context.short_store,
          now: context.now
        )

      :mid ->
        Basic.remember(target, decorated_attrs,
          namespace: context.namespace,
          store: context.mid_store,
          now: context.now
        )

      :long ->
        context.long_term_store.module.remember(
          target,
          decorated_attrs,
          long_term_runtime_opts(context, now: context.now)
        )
    end
  end

  defp build_query(%Query{} = query), do: {:ok, query}

  defp build_query(query_attrs) when is_map(query_attrs) do
    query_attrs
    |> Map.drop([:provider, "provider", :tier, "tier", :tiers, "tiers", :tier_mode, "tier_mode"])
    |> Query.new()
  end

  defp resolve_context(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    provider_opts = normalize_keyword(Keyword.get(opts, :provider_opts, []))
    now = Keyword.get(opts, :now, System.system_time(:millisecond))

    with {:ok, namespace} <- resolve_namespace(target, attrs, opts, provider_opts),
         {:ok, short_store} <- normalize_store_pair(resolve_short_store_input(provider_opts, attrs, opts)),
         {:ok, mid_store} <- normalize_store_pair(resolve_mid_store_input(provider_opts, attrs, opts)),
         {:ok, long_term_store} <- normalize_long_term_store(resolve_long_term_input(provider_opts, attrs, opts)),
         :ok <- ensure_store_ready(short_store),
         :ok <- ensure_store_ready(mid_store),
         {:ok, long_term_meta} <- long_term_store.module.init(long_term_store.opts) do
      {:ok,
       %{
         namespace: namespace,
         now: now,
         short_store: short_store,
         mid_store: mid_store,
         long_term_store: %{module: long_term_store.module, opts: long_term_store.opts, meta: long_term_meta},
         lifecycle: normalize_lifecycle(resolve_lifecycle(provider_opts, opts))
       }}
    end
  end

  defp resolve_namespace(target, attrs, opts, provider_opts) do
    explicit = pick_value(opts, attrs, :namespace)
    from_provider = Keyword.get(provider_opts, :namespace)

    resolved =
      cond do
        present_string?(explicit) -> String.trim(explicit)
        present_string?(from_provider) -> String.trim(from_provider)
        is_binary(target_id(target)) -> "agent:" <> target_id(target)
        true -> nil
      end

    if is_binary(resolved), do: {:ok, resolved}, else: {:error, :namespace_required}
  end

  defp resolve_short_store_input(provider_opts, attrs \\ %{}, opts \\ []) do
    store =
      pick_value(opts, attrs, :short_store) ||
        pick_value(opts, attrs, :store) ||
        Keyword.get(provider_opts, :short_store) ||
        Keyword.get(provider_opts, :store) ||
        @default_short_store

    store_opts =
      pick_value(opts, attrs, :short_store_opts, pick_value(opts, attrs, :store_opts, [])) ||
        Keyword.get(provider_opts, :short_store_opts) ||
        Keyword.get(provider_opts, :store_opts, [])

    {store, store_opts}
  end

  defp resolve_mid_store_input(provider_opts, attrs \\ %{}, opts \\ []) do
    store =
      pick_value(opts, attrs, :mid_store) ||
        Keyword.get(provider_opts, :mid_store) ||
        @default_mid_store

    store_opts =
      pick_value(opts, attrs, :mid_store_opts, []) ||
        Keyword.get(provider_opts, :mid_store_opts, [])

    {store, store_opts}
  end

  defp resolve_long_term_input(provider_opts, attrs \\ %{}, opts \\ []) do
    backend =
      pick_value(opts, attrs, :long_term_store) ||
        Keyword.get(provider_opts, :long_term_store) ||
        @default_long_term_store

    backend_opts =
      pick_value(opts, attrs, :long_term_store_opts, []) ||
        Keyword.get(provider_opts, :long_term_store_opts, [])

    {backend, backend_opts}
  end

  defp resolve_lifecycle(provider_opts, opts) do
    opts[:lifecycle] || Keyword.get(provider_opts, :lifecycle, @default_lifecycle)
  end

  defp normalize_store_pair({store, override_opts}) do
    with {:ok, {store_mod, base_opts}} <- Store.normalize_store(store),
         true <- is_list(override_opts) do
      {:ok, {store_mod, Keyword.merge(base_opts, override_opts)}}
    else
      false -> {:error, :invalid_store_opts}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_long_term_store({backend, override_opts}) do
    with {:ok, ref} <- normalize_long_term_ref(backend),
         true <- is_list(override_opts),
         opts <- Keyword.merge(ref.opts, override_opts),
         :ok <- ref.module.validate_config(opts) do
      {:ok, %{module: ref.module, opts: opts}}
    else
      false -> {:error, :invalid_long_term_store_opts}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_long_term_ref({module, opts}) when is_atom(module) and is_list(opts) do
    validate_long_term_ref(%{module: module, opts: opts})
  end

  defp normalize_long_term_ref(module) when is_atom(module) do
    validate_long_term_ref(%{module: module, opts: []})
  end

  defp normalize_long_term_ref(other), do: {:error, {:invalid_long_term_store, other}}

  defp validate_long_term_ref(%{module: module} = ref) do
    with {:ok, loaded} <- ensure_loaded(module),
         :ok <- ensure_long_term_callbacks(loaded) do
      {:ok, %{ref | module: loaded}}
    else
      {:error, _reason} = error -> error
    end
  end

  defp ensure_loaded(module) do
    case Code.ensure_loaded(module) do
      {:module, loaded} -> {:ok, loaded}
      {:error, reason} -> {:error, {:invalid_long_term_store, {module, reason}}}
    end
  end

  defp ensure_long_term_callbacks(module) do
    missing =
      Enum.reject(@required_long_term_callbacks, fn {name, arity} ->
        function_exported?(module, name, arity)
      end)

    if missing == [] do
      :ok
    else
      {:error, {:invalid_long_term_store_callbacks, module, missing}}
    end
  end

  defp long_term_runtime_opts(context, extra_opts) do
    context.long_term_store.opts
    |> Keyword.put(:namespace, context.namespace)
    |> Keyword.merge(extra_opts)
  end

  defp resolve_single_tier(attrs, opts, default) do
    case resolve_tiers(attrs, opts, default: default) do
      {:ok, [tier]} -> {:ok, tier}
      {:ok, _tiers} -> {:error, :invalid_tier}
      {:error, _reason} = error -> error
    end
  end

  defp resolve_tiers(%Query{} = query, opts, config) do
    value =
      pick_value(opts, %{}, :tiers) ||
        pick_value(opts, %{}, :tier_mode) ||
        pick_value(opts, %{}, :tier) ||
        tiered_extension_value(query.extensions, :tiers) ||
        tiered_extension_value(query.extensions, :tier_mode) ||
        tiered_extension_value(query.extensions, :tier) ||
        Keyword.get(config, :default, :all)

    normalize_tiers(value)
  end

  defp resolve_tiers(attrs, opts, config) do
    value =
      pick_value(opts, attrs, :tiers) ||
        pick_value(opts, attrs, :tier_mode) ||
        pick_value(opts, attrs, :tier) ||
        tiered_extension_value(attrs, :tiers) ||
        tiered_extension_value(attrs, :tier_mode) ||
        tiered_extension_value(attrs, :tier) ||
        Keyword.get(config, :default, :all)

    normalize_tiers(value)
  end

  defp tiered_extension_value(%{} = attrs, key) when is_atom(key) do
    with %{} = tiered <- resolve_tiered_extension(attrs) do
      Map.get(tiered, key, Map.get(tiered, Atom.to_string(key)))
    else
      _ -> nil
    end
  end

  defp tiered_extension_value(_attrs, _key), do: nil

  defp resolve_tiered_extension(%{} = attrs) do
    direct_tiered = Map.get(attrs, :tiered, Map.get(attrs, "tiered"))
    query_extensions = Map.get(attrs, :query_extensions, Map.get(attrs, "query_extensions"))

    case direct_tiered do
      %{} = tiered ->
        tiered

      _ ->
        with nil <- extract_tiered_extension(query_extensions),
             %{} = extensions <- Map.get(attrs, :extensions, Map.get(attrs, "extensions")),
             %{} = tiered <- Map.get(extensions, :tiered, Map.get(extensions, "tiered")) do
          tiered
        else
          %{} = tiered -> tiered
          _ -> nil
        end
    end
  end

  defp extract_tiered_extension(%{} = extensions) do
    Map.get(extensions, :tiered, Map.get(extensions, "tiered"))
  end

  defp extract_tiered_extension(_extensions), do: nil

  defp normalize_tiers(:all), do: {:ok, [:short, :mid, :long]}
  defp normalize_tiers(nil), do: {:ok, [:short, :mid, :long]}
  defp normalize_tiers(tier) when tier in [:short, :mid, :long], do: {:ok, [tier]}

  defp normalize_tiers(tiers) when is_list(tiers) do
    tiers = Enum.uniq(Enum.filter(tiers, &(&1 in [:short, :mid, :long])))
    if tiers == [], do: {:error, :invalid_tier}, else: {:ok, tiers}
  end

  defp normalize_tiers(_tiers), do: {:error, :invalid_tier}

  defp decorate_attrs(attrs, tier, now) when is_map(attrs) do
    metadata = attrs |> map_get(:metadata, %{}) |> normalize_map()
    tiered = tiered_metadata(metadata)
    importance = resolve_importance(attrs, metadata, tiered)

    updated_tiered =
      tiered
      |> Map.put(:tier, tier)
      |> Map.put(:importance, importance)
      |> Map.put(:promotion_score, tiered[:promotion_score] || importance)
      |> Map.put(:last_accessed_at, now)
      |> Map.put_new(:promotion_count, tiered[:promotion_count] || 0)

    attrs
    |> Map.drop([
      :provider,
      "provider",
      :tier,
      "tier",
      :tier_mode,
      "tier_mode",
      :tiers,
      "tiers",
      :importance,
      "importance"
    ])
    |> Map.put(:metadata, Map.put(metadata, :tiered, updated_tiered))
  end

  defp promoted_record(%Record{} = record, source_tier, destination_tier, score, threshold, now) do
    metadata = normalize_map(record.metadata)
    tiered = tiered_metadata(record)
    lifecycle = lifecycle_metadata(tiered)

    promoted_tiered =
      tiered
      |> Map.put(:tier, destination_tier)
      |> Map.put(:promotion_score, score)
      |> Map.put(:last_promoted_at, now)
      |> Map.put(:last_accessed_at, now)
      |> Map.put(:promoted_from, source_tier)
      |> Map.update(:promotion_count, 1, &(&1 + 1))
      |> Map.put(
        :lifecycle,
        lifecycle
        |> Map.put(:last_evaluated_at, now)
        |> Map.put(:last_decision, :promoted)
        |> Map.put(:last_source_tier, source_tier)
        |> Map.put(:last_destination_tier, destination_tier)
        |> Map.put(:last_score, score)
        |> Map.put(:last_threshold, threshold)
        |> Map.put(:last_skip_reason, nil)
        |> Map.update(:evaluation_count, 1, &(&1 + 1))
      )

    %Record{record | metadata: Map.put(metadata, :tiered, promoted_tiered)}
  end

  defp lifecycle_evaluated_record(
         %Record{} = record,
         source_tier,
         destination_tier,
         score,
         threshold,
         decision,
         reason,
         now
       ) do
    metadata = normalize_map(record.metadata)
    tiered = tiered_metadata(record)
    lifecycle = lifecycle_metadata(tiered)

    updated_lifecycle =
      lifecycle
      |> Map.put(:last_evaluated_at, now)
      |> Map.put(:last_decision, decision)
      |> Map.put(:last_source_tier, source_tier)
      |> Map.put(:last_destination_tier, destination_tier)
      |> Map.put(:last_score, score)
      |> Map.put(:last_threshold, threshold)
      |> Map.put(:last_skip_reason, reason)
      |> Map.update(:evaluation_count, 1, &(&1 + 1))
      |> Map.update(:skip_count, 1, &(&1 + 1))

    updated_tiered =
      tiered
      |> Map.put(:promotion_score, score)
      |> Map.put(:lifecycle, updated_lifecycle)

    %Record{record | metadata: Map.put(metadata, :tiered, updated_tiered)}
  end

  defp promotion_score(%Record{} = record) do
    tiered = tiered_metadata(record)
    importance = normalize_score(tiered[:importance] || 0.0)
    promotion_bonus = min((tiered[:promotion_count] || 0) * 0.05, 0.15)

    clamp_score(
      importance * 0.7 +
        long_text_bonus(record.text, 80, 0.1) +
        important_tag_bonus(record.tags, 0.15) +
        class_importance_bonus(record.class) +
        promotion_bonus
    )
  end

  defp resolve_importance(attrs, metadata, tiered) do
    attrs_importance = map_get(attrs, :importance)
    metadata_importance = map_get(metadata, :importance)
    tiered_importance = tiered[:importance]

    cond do
      is_number(attrs_importance) -> normalize_score(attrs_importance)
      is_number(metadata_importance) -> normalize_score(metadata_importance)
      is_number(tiered_importance) -> normalize_score(tiered_importance)
      true -> inferred_importance(attrs)
    end
  end

  defp inferred_importance(attrs) do
    class = map_get(attrs, :class, :episodic)
    text = map_get(attrs, :text)
    tags = map_get(attrs, :tags, [])

    clamp_score(
      base_importance(class) +
        tag_presence_bonus(tags, 0.05) +
        important_tag_bonus(tags, 0.1) +
        long_text_bonus(text, 120, 0.05)
    )
  end

  defp tiered_metadata(%Record{} = record) do
    record.metadata |> normalize_map() |> tiered_metadata()
  end

  defp tiered_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.get(:tiered, Map.get(metadata, "tiered", %{}))
    |> normalize_map()
  end

  defp lifecycle_metadata(%{} = tiered) do
    tiered
    |> Map.get(:lifecycle, Map.get(tiered, "lifecycle", %{}))
    |> normalize_map()
  end

  defp build_explanation(%Query{} = query, context, requested_tiers, bundles) do
    result_entries =
      bundles
      |> Enum.flat_map(fn bundle ->
        Enum.map(bundle.records, fn record -> %{tier: bundle.tier, record: record} end)
      end)
      |> sort_result_entries(query.order)
      |> Enum.uniq_by(& &1.record.id)
      |> Enum.take(query.limit)
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, rank} ->
        explain_result_entry(entry, rank, query)
      end)

    counts_by_tier = counts_by_tier(bundles)

    %{
      provider: __MODULE__,
      namespace: context.namespace,
      query: summarize_query(query),
      requested_tiers: requested_tiers,
      participating_tiers: participating_tiers(counts_by_tier, requested_tiers),
      result_count: length(result_entries),
      results: result_entries,
      extensions: %{
        tiered: %{
          payload_version: 1,
          counts_by_tier: counts_by_tier,
          ranking: %{
            primary: :observed_at,
            tie_breaker: :id,
            order: query.order,
            tier_signal: :promotion_score
          }
        }
      }
    }
  end

  defp build_lifecycle_snapshot(context, requested_tiers, bundles) do
    records =
      bundles
      |> Enum.flat_map(fn bundle ->
        Enum.map(bundle.records, fn record ->
          summarize_lifecycle_record(bundle.tier, record)
        end)
      end)
      |> Enum.filter(&is_map/1)
      |> Enum.sort_by(&{&1.last_evaluated_at || 0, &1.id}, :desc)

    %{
      provider: __MODULE__,
      namespace: context.namespace,
      requested_tiers: requested_tiers,
      thresholds: %{
        short_to_mid: Keyword.fetch!(context.lifecycle, :short_to_mid_threshold),
        mid_to_long: Keyword.fetch!(context.lifecycle, :mid_to_long_threshold)
      },
      current_tiers: counts_by_tier(bundles),
      recent_outcomes: summarize_recent_outcomes(records),
      totals: %{
        tracked_records: length(records),
        promoted: Enum.count(records, &(&1.decision == :promoted)),
        skipped: Enum.count(records, &(&1.decision == :skipped))
      },
      records: records
    }
  end

  defp summarize_lifecycle_record(tier, %Record{} = record) do
    tiered = tiered_metadata(record)
    lifecycle = lifecycle_metadata(tiered)

    if lifecycle == %{} do
      nil
    else
      %{
        id: record.id,
        tier: tier,
        decision: lifecycle[:last_decision],
        source_tier: lifecycle[:last_source_tier],
        destination_tier: lifecycle[:last_destination_tier],
        score: normalize_score(lifecycle[:last_score]),
        threshold: normalize_score(lifecycle[:last_threshold]),
        skip_reason: lifecycle[:last_skip_reason],
        promotion_count: tiered[:promotion_count] || 0,
        evaluation_count: lifecycle[:evaluation_count] || 0,
        last_evaluated_at: lifecycle[:last_evaluated_at]
      }
    end
  end

  defp summarize_recent_outcomes(records) do
    base = %{
      short: %{destination_tier: :mid, promoted: 0, skipped: 0, skipped_reasons: %{}},
      mid: %{destination_tier: :long, promoted: 0, skipped: 0, skipped_reasons: %{}},
      long: %{destination_tier: nil, promoted: 0, skipped: 0, skipped_reasons: %{}}
    }

    Enum.reduce(records, base, &update_recent_outcomes_for_record/2)
  end

  defp update_recent_outcomes_for_record(record, acc) do
    case record.source_tier do
      source_tier when source_tier in [:short, :mid, :long] ->
        update_in(acc, [source_tier], &update_recent_outcome_summary(&1, record))

      _other ->
        acc
    end
  end

  defp update_recent_outcome_summary(summary, %{decision: :promoted}) do
    Map.update!(summary, :promoted, &(&1 + 1))
  end

  defp update_recent_outcome_summary(summary, %{decision: :skipped, skip_reason: reason}) do
    summary
    |> Map.update!(:skipped, &(&1 + 1))
    |> update_in([:skipped_reasons, reason], fn count -> (count || 0) + 1 end)
  end

  defp update_recent_outcome_summary(summary, _record), do: summary

  defp explain_result_entry(%{tier: tier, record: %Record{} = record}, rank, %Query{} = query) do
    tiered = tiered_metadata(record)

    %{
      id: record.id,
      tier: tier,
      rank: rank,
      matched_on: matched_on(record, query),
      ranking_context: %{
        observed_at: record.observed_at,
        order: query.order
      },
      extensions: %{
        tiered: %{
          importance: normalize_score(tiered[:importance]),
          promotion_score: promotion_score(record),
          promotion_count: tiered[:promotion_count] || 0,
          promoted_from: tiered[:promoted_from]
        }
      }
    }
  end

  defp summarize_query(%Query{} = query) do
    %{
      classes: query.classes,
      kinds: query.kinds,
      tags_any: query.tags_any,
      tags_all: query.tags_all,
      text_contains: query.text_contains,
      since: query.since,
      until: query.until,
      limit: query.limit,
      order: query.order
    }
  end

  defp matched_on(%Record{}, %Query{} = query) do
    []
    |> maybe_add_match(query.classes != [], :class)
    |> maybe_add_match(query.kinds != [], :kind)
    |> maybe_add_match(query.tags_any != [], :tags_any)
    |> maybe_add_match(query.tags_all != [], :tags_all)
    |> maybe_add_match(is_binary(query.text_contains), :text_contains)
    |> maybe_add_match(is_integer(query.since), :since)
    |> maybe_add_match(is_integer(query.until), :until)
    |> case do
      [] -> [:namespace]
      matches -> matches
    end
  end

  defp maybe_add_match(matches, true, match), do: matches ++ [match]
  defp maybe_add_match(matches, false, _match), do: matches

  defp empty_promotion_result(source_tier, destination_tier, threshold) do
    %{
      source_tier: source_tier,
      destination_tier: destination_tier,
      threshold: threshold,
      examined: 0,
      promoted: 0,
      skipped: 0,
      ids: [],
      skipped_ids: [],
      decisions: []
    }
  end

  defp accumulate_promotion_outcome(result, %{decision: :promoted} = outcome) do
    result
    |> Map.update!(:promoted, &(&1 + 1))
    |> Map.update!(:ids, &[outcome.id | &1])
    |> Map.update!(:decisions, &[outcome | &1])
  end

  defp accumulate_promotion_outcome(result, %{decision: :skipped} = outcome) do
    result
    |> Map.update!(:skipped, &(&1 + 1))
    |> Map.update!(:skipped_ids, &[outcome.id | &1])
    |> Map.update!(:decisions, &[outcome | &1])
  end

  defp promotion_outcome(record, decision, source_tier, destination_tier, score, threshold, reason \\ nil) do
    %{
      id: record.id,
      decision: decision,
      source_tier: source_tier,
      destination_tier: destination_tier,
      score: score,
      threshold: threshold,
      reason: reason
    }
  end

  defp counts_by_tier(bundles) do
    base = %{short: 0, mid: 0, long: 0}

    Enum.reduce(bundles, base, fn %{tier: tier, records: records}, acc ->
      Map.put(acc, tier, length(records))
    end)
  end

  defp participating_tiers(counts_by_tier, requested_tiers) do
    Enum.filter(requested_tiers, fn tier -> Map.get(counts_by_tier, tier, 0) > 0 end)
  end

  defp sort_result_entries(entries, :asc) do
    Enum.sort_by(entries, fn %{record: record} -> {record.observed_at, record.id} end, :asc)
  end

  defp sort_result_entries(entries, :desc) do
    Enum.sort_by(entries, fn %{record: record} -> {record.observed_at, record.id} end, :desc)
  end

  defp sort_records(records, :asc), do: Enum.sort_by(records, &{&1.observed_at, &1.id}, :asc)
  defp sort_records(records, :desc), do: Enum.sort_by(records, &{&1.observed_at, &1.id}, :desc)

  defp normalize_lifecycle(opts) do
    @default_lifecycle
    |> Keyword.merge(normalize_keyword(opts))
  end

  defp validate_lifecycle(opts) when is_list(opts) do
    short_threshold =
      Keyword.get(opts, :short_to_mid_threshold, Keyword.fetch!(@default_lifecycle, :short_to_mid_threshold))

    mid_threshold =
      Keyword.get(opts, :mid_to_long_threshold, Keyword.fetch!(@default_lifecycle, :mid_to_long_threshold))

    with :ok <- validate_threshold(short_threshold) do
      validate_threshold(mid_threshold)
    end
  end

  defp validate_lifecycle(_opts), do: {:error, :invalid_lifecycle_opts}

  defp validate_threshold(value) when is_number(value) and value >= 0.0 and value <= 1.0, do: :ok
  defp validate_threshold(_value), do: {:error, :invalid_lifecycle_threshold}

  defp validate_namespace(nil), do: :ok
  defp validate_namespace(value) when is_binary(value) or is_atom(value), do: :ok
  defp validate_namespace(_value), do: {:error, :invalid_namespace}

  defp ensure_store_ready({store_mod, store_opts}), do: store_mod.ensure_ready(store_opts)

  defp normalize_optional_namespace(nil), do: nil
  defp normalize_optional_namespace(namespace) when is_binary(namespace), do: String.trim(namespace)
  defp normalize_optional_namespace(namespace) when is_atom(namespace), do: Atom.to_string(namespace)
  defp normalize_optional_namespace(_namespace), do: nil

  defp normalize_direct_opts(target, opts) when is_list(opts) do
    with {:ok, normalized_opts} <- unwrap_direct_opts(opts) do
      case {Keyword.has_key?(normalized_opts, :provider_opts), target_provider_opts(target)} do
        {true, _provider_opts} ->
          {:ok, normalized_opts}

        {false, provider_opts} when is_list(provider_opts) ->
          {:ok, Keyword.put(normalized_opts, :provider_opts, provider_opts)}

        {false, _provider_opts} ->
          {:ok, normalized_opts}
      end
    end
  end

  defp normalize_direct_opts(_target, _opts), do: {:error, :invalid_provider_opts}

  defp unwrap_direct_opts(opts) when is_list(opts) do
    case Keyword.get(opts, :provider) do
      nil ->
        {:ok, opts}

      __MODULE__ ->
        {:ok, Keyword.delete(opts, :provider)}

      {__MODULE__, provider_opts} when is_list(provider_opts) ->
        {:ok,
         opts
         |> Keyword.put_new(:provider_opts, provider_opts)
         |> Keyword.delete(:provider)}

      other ->
        {:error, {:invalid_provider, other}}
    end
  end

  defp unwrap_direct_opts(_opts), do: {:error, :invalid_provider_opts}

  defp target_provider_opts(%{state: %{} = state}) do
    state
    |> Map.get(Jido.Memory.Runtime.plugin_state_key(), %{})
    |> target_provider_opts()
  end

  defp target_provider_opts(%{} = map) do
    case Map.get(map, :provider) do
      %{module: __MODULE__, opts: opts} when is_list(opts) -> opts
      _ -> nil
    end
  end

  defp target_provider_opts(_target), do: nil

  defp normalize_keyword(opts) when is_list(opts), do: opts
  defp normalize_keyword(_opts), do: []

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

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false

  defp normalize_score(value) when is_integer(value), do: clamp_score(value / 1)
  defp normalize_score(value) when is_float(value), do: clamp_score(value)
  defp normalize_score(_value), do: 0.0

  defp base_importance(:semantic), do: 0.8
  defp base_importance(:procedural), do: 0.75
  defp base_importance(:episodic), do: 0.55
  defp base_importance(:working), do: 0.3
  defp base_importance(_class), do: 0.5

  defp class_importance_bonus(:semantic), do: 0.12
  defp class_importance_bonus(:procedural), do: 0.1
  defp class_importance_bonus(:episodic), do: 0.05
  defp class_importance_bonus(_class), do: 0.0

  defp tag_presence_bonus(tags, bonus) when is_list(tags) and tags != [], do: bonus
  defp tag_presence_bonus(_tags, _bonus), do: 0.0

  defp important_tag_bonus(tags, bonus) when is_list(tags) do
    if Enum.any?(tags, &(to_string(&1) in ["important", "pinned", "memory:important"])),
      do: bonus,
      else: 0.0
  end

  defp important_tag_bonus(_tags, _bonus), do: 0.0

  defp long_text_bonus(text, min_length, bonus) when is_binary(text) do
    if String.length(String.trim(text)) >= min_length, do: bonus, else: 0.0
  end

  defp long_text_bonus(_text, _min_length, _bonus), do: 0.0

  defp clamp_score(value) when value < 0.0, do: 0.0
  defp clamp_score(value) when value > 1.0, do: 1.0
  defp clamp_score(value), do: Float.round(value * 1.0, 4)
end
