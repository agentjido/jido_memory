defmodule Jido.Memory.Provider.Mem0 do
  @moduledoc """
  Built-in Mem0-style provider baseline.

  The first cut keeps the canonical `Jido.Memory.Provider` surface and uses the
  existing store-backed core flow while reserving metadata and capabilities for
  later extraction, reconciliation, scoped identity, and graph augmentation
  work.
  """

  @behaviour Jido.Memory.Provider
  @behaviour Jido.Memory.Capability.Ingestion
  @behaviour Jido.Memory.Capability.ExplainableRetrieval

  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.{Query, Record, Store}

  @default_extraction [recent_window: 6, summary_context: :optional]
  @default_retrieval [
    mode: :balanced,
    graph_augmentation: [enabled: false, include_relationships: true, relationship_limit: 5]
  ]
  @scope_dimensions [:user_id, :agent_id, :app_id, :run_id]
  @scope_source_precedence [:runtime_opts, :target, :provider_config]
  @supported_mem0_query_extensions [:scope, :retrieval_mode, :fact_key, :graph]

  @capabilities %{
    core: true,
    retrieval: %{
      explainable: true,
      active: false,
      memory_types: false,
      provider_extensions: true,
      scoped: true,
      graph_augmentation: true
    },
    lifecycle: %{consolidate: false, inspect: false},
    ingestion: %{batch: true, multimodal: false, routed: true, access: :provider_direct},
    operations: %{
      feedback: :provider_direct,
      export: :provider_direct,
      history: :provider_direct,
      maintenance: :provider_direct
    },
    governance: %{protected_memory: false, exact_preservation: false, access: :none},
    hooks: %{}
  }

  @impl true
  def validate_config(opts) when is_list(opts) do
    with :ok <- Basic.validate_config(opts),
         :ok <- validate_scoped_identity(Keyword.get(opts, :scoped_identity, [])),
         :ok <- validate_extraction_config(Keyword.get(opts, :extraction, @default_extraction)) do
      validate_retrieval_config(Keyword.get(opts, :retrieval, @default_retrieval))
    end
  end

  def validate_config(_opts), do: {:error, :invalid_provider_opts}

  @impl true
  def child_specs(_opts), do: []

  @impl true
  def init(opts) do
    with :ok <- validate_config(opts),
         {:ok, basic_meta} <- Basic.init(opts),
         {:ok, scoped_identity} <- scoped_identity_meta(opts) do
      {:ok,
       basic_meta
       |> Map.put(:provider, __MODULE__)
       |> Map.put(:capabilities, @capabilities)
       |> Map.put(:provider_style, :mem0)
       |> Map.put(:topology, %{
         archetype: :extraction_reconciliation,
         retrieval: %{
           scoped: true,
           explainable: true,
           graph_augmentation: true,
           query_extensions: @supported_mem0_query_extensions
         },
         maintenance: %{
           reconciliation: :provider_direct,
           feedback: :provider_direct,
           export: :provider_direct,
           history: :provider_direct,
           summary_refresh: :provider_direct,
           reconciliation_rerun: :provider_direct,
           outcomes: [:add, :update, :delete, :noop],
           similarity_strategy: :fact_key_and_text
         }
       })
       |> Map.put(:advanced_operations, advanced_operations_meta())
       |> Map.put(:surface_boundary, surface_boundary_meta())
       |> Map.put(:extraction_context, extraction_context_meta(opts))
       |> Map.put(:retrieval_context, retrieval_context_meta(opts))
       |> Map.put(:scoped_identity, scoped_identity)}
    end
  end

  @impl true
  def capabilities(provider_meta), do: Map.get(provider_meta, :capabilities, @capabilities)

  @impl true
  def remember(target, attrs, opts) when is_list(attrs), do: remember(target, Map.new(attrs), opts)

  def remember(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    with {:ok, context, scope} <- resolve_mem0_context(target, attrs, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, record} <- build_record(attrs, context.namespace, context.now, scope, %{write_mode: :direct}) do
      with {:ok, stored_record} <- context.store_mod.put(record, context.store_opts) do
        maybe_log_history_event(context, scope, :remember, %{
          record_id: stored_record.id,
          class: stored_record.class,
          kind: stored_record.kind,
          text: stored_record.text,
          write_mode: :direct
        })

        {:ok, stored_record}
      end
    end
  end

  def remember(_target, _attrs, _opts), do: {:error, :invalid_attrs}

  @impl true
  def get(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, context, scope} <- resolve_mem0_context(target, %{}, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, record} <- Store.fetch(context.store_mod, {context.namespace, id}, context.store_opts),
         true <- scope_matches?(record, scope) do
      {:ok, record}
    else
      false -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def get(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def retrieve(target, %Query{} = query, opts) when is_list(opts) do
    with {:ok, context} <- resolve_retrieval_context(target, query, opts) do
      do_retrieve_records(query, context)
    end
  end

  def retrieve(target, query_attrs, opts) when is_list(query_attrs),
    do: retrieve(target, Map.new(query_attrs), opts)

  def retrieve(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with {:ok, query} <- build_query(query_attrs, nil),
         {:ok, context} <- resolve_retrieval_context(target, query, opts) do
      do_retrieve_records(query, context)
    end
  end

  def retrieve(_target, _query, _opts), do: {:error, :invalid_query}

  @impl true
  def explain_retrieval(target, %Query{} = query, opts) when is_list(opts) do
    with {:ok, context} <- resolve_retrieval_context(target, query, opts),
         {:ok, records} <- do_retrieve_records(query, context) do
      {:ok, build_explanation(query, context, records)}
    end
  end

  def explain_retrieval(target, query_attrs, opts) when is_list(query_attrs),
    do: explain_retrieval(target, Map.new(query_attrs), opts)

  def explain_retrieval(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with {:ok, query} <- build_query(query_attrs, nil),
         {:ok, context} <- resolve_retrieval_context(target, query, opts),
         {:ok, records} <- do_retrieve_records(query, context) do
      {:ok, build_explanation(query, context, records)}
    end
  end

  def explain_retrieval(_target, _query, _opts), do: {:error, :invalid_query}

  @impl true
  def forget(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, context, scope} <- resolve_mem0_context(target, %{}, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts) do
      case context.store_mod.get({context.namespace, id}, context.store_opts) do
        {:ok, record} ->
          maybe_forget_scoped_record(record, context, scope, id)

        :not_found ->
          {:ok, false}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def forget(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def prune(target, opts), do: Basic.prune(target, opts)

  @impl true
  def ingest(target, %{} = payload, opts) when is_list(opts) do
    with {:ok, normalized_opts} <- normalize_direct_opts(target, opts),
         {:ok, context, scope} <- resolve_mem0_context(target, %{}, normalized_opts),
         {:ok, extraction_config} <- extraction_config(normalized_opts),
         {:ok, normalized_payload} <- normalize_ingest_payload(payload, extraction_config),
         {:ok, extracted} <- extract_candidates(normalized_payload, extraction_config) do
      persist_extracted_candidates(extracted, context, scope, normalized_payload)
    end
  end

  def ingest(_target, _payload, _opts), do: {:error, :invalid_ingest_payload}

  @doc """
  Records provider-direct feedback for a scoped Mem0 memory record.
  """
  @spec feedback(map() | struct(), binary(), atom() | map() | keyword(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def feedback(target, record_id, feedback, opts \\ [])

  def feedback(target, record_id, feedback, opts) when is_binary(record_id) and is_list(opts) do
    with {:ok, normalized_opts} <- normalize_direct_opts(target, opts),
         {:ok, context, scope} <- resolve_mem0_context(target, %{}, normalized_opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, record} <- Store.fetch(context.store_mod, {context.namespace, record_id}, context.store_opts),
         true <- scope_matches?(record, scope) || {:error, :not_found},
         {:ok, feedback_attrs} <- normalize_feedback(feedback),
         {:ok, updated_record} <- persist_feedback(record, context, feedback_attrs) do
      maybe_log_history_event(context, scope, :feedback, %{
        record_id: updated_record.id,
        fact_key: fact_key(updated_record),
        status: feedback_attrs.status,
        note: feedback_attrs.note,
        source: feedback_attrs.source
      })

      {:ok,
       %{
         provider: __MODULE__,
         record_id: updated_record.id,
         feedback: %{
           status: feedback_attrs.status,
           note: feedback_attrs.note,
           source: feedback_attrs.source,
           count: feedback_count(updated_record)
         },
         scope: scope
       }}
    end
  end

  def feedback(_target, _record_id, _feedback, _opts), do: {:error, :invalid_feedback}

  @doc """
  Returns provider-direct Mem0 history events for the current effective scope.
  """
  @spec history(map() | struct(), keyword()) :: {:ok, map()} | {:error, term()}
  def history(target, opts \\ [])

  def history(target, opts) when is_list(opts) do
    with {:ok, normalized_opts} <- normalize_direct_opts(target, opts),
         {:ok, context, scope} <- resolve_mem0_context(target, %{}, normalized_opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, filters} <- history_filters(normalized_opts),
         {:ok, records} <- history_records(context, scope, filters) do
      {:ok,
       %{
         provider: __MODULE__,
         namespace: context.namespace,
         scope: scope,
         filters: filters,
         count: length(records),
         events: Enum.map(records, &history_event/1)
       }}
    end
  end

  def history(_target, _opts), do: {:error, :invalid_provider_opts}

  @doc """
  Returns a provider-direct scoped export snapshot for Mem0-managed records.
  """
  @spec export(map() | struct(), keyword()) :: {:ok, map()} | {:error, term()}
  def export(target, opts \\ [])

  def export(target, opts) when is_list(opts) do
    with {:ok, normalized_opts} <- normalize_direct_opts(target, opts),
         {:ok, context, scope} <- resolve_mem0_context(target, %{}, normalized_opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, filters} <- export_filters(normalized_opts),
         {:ok, records} <- export_records(context, scope, filters) do
      history =
        if filters.include_history do
          history_records(context, scope, %{
            record_id: nil,
            fact_key: nil,
            event_types: [],
            limit: filters.history_limit
          })
        else
          {:ok, []}
        end

      case history do
        {:ok, history_records} ->
          {:ok,
           %{
             provider: __MODULE__,
             namespace: context.namespace,
             scope: scope,
             count: length(records),
             filters: filters,
             records: Enum.map(records, &export_record/1),
             history_count: length(history_records),
             history: Enum.map(history_records, &history_event/1)
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def export(_target, _opts), do: {:error, :invalid_provider_opts}

  @doc """
  Returns a provider-direct maintenance snapshot for the current scoped Mem0 state.
  """
  @spec refresh_summary(map() | struct(), keyword()) :: {:ok, map()} | {:error, term()}
  def refresh_summary(target, opts \\ [])

  def refresh_summary(target, opts) when is_list(opts) do
    with {:ok, normalized_opts} <- normalize_direct_opts(target, opts),
         {:ok, context, scope} <- resolve_mem0_context(target, %{}, normalized_opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, records} <-
           export_records(context, scope, %{
             classes: [],
             kinds: [],
             limit: 500,
             include_history: false,
             history_limit: 0
           }),
         {:ok, events} <- history_records(context, scope, %{record_id: nil, fact_key: nil, event_types: [], limit: 100}) do
      {:ok,
       %{
         provider: __MODULE__,
         namespace: context.namespace,
         scope: scope,
         totals: %{
           records: length(records),
           maintained_records: Enum.count(records, &(maintenance_action(&1) != nil)),
           feedback_tracked: Enum.count(records, &(feedback_status(&1) != nil))
         },
         counts_by_class: counts_by(records, & &1.class),
         counts_by_kind: counts_by(records, & &1.kind),
         feedback: counts_by(records, &feedback_status/1),
         maintenance_actions: counts_by(records, &maintenance_action/1),
         history_events: counts_by(events, &history_event_type/1),
         recent_history: Enum.map(Enum.take(events, 10), &history_event/1)
       }}
    end
  end

  def refresh_summary(_target, _opts), do: {:error, :invalid_provider_opts}

  @doc """
  Re-runs provider-owned Mem0 reconciliation explicitly as a maintenance operation.
  """
  @spec rerun_reconciliation(map() | struct(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def rerun_reconciliation(target, payload, opts \\ [])

  def rerun_reconciliation(target, %{} = payload, opts) when is_list(opts) do
    case ingest(target, payload, opts) do
      {:ok, result} -> {:ok, Map.put(result, :maintenance_mode, :rerun)}
      {:error, reason} -> {:error, reason}
    end
  end

  def rerun_reconciliation(_target, _payload, _opts), do: {:error, :invalid_ingest_payload}

  @impl true
  def info(provider_meta, :all), do: {:ok, provider_meta}

  def info(provider_meta, fields) when is_list(fields) do
    {:ok, Map.take(provider_meta, fields)}
  end

  def info(_provider_meta, _fields), do: {:error, :invalid_info_fields}

  @doc false
  @spec resolve_scope(map() | struct(), keyword()) :: {:ok, map()} | {:error, term()}
  def resolve_scope(target, opts) when is_list(opts) do
    provider_opts = normalize_provider_opts(Keyword.get(opts, :provider_opts, []))

    with {:ok, defaults} <- normalize_scoped_identity(Keyword.get(provider_opts, :scoped_identity, [])) do
      {:ok,
       Enum.reduce(@scope_dimensions, %{}, fn dimension, acc ->
         Map.put(acc, dimension, resolve_scope_value(dimension, target, opts, defaults))
       end)}
    end
  end

  def resolve_scope(_target, _opts), do: {:error, :invalid_provider_opts}

  defp resolve_mem0_context(target, attrs, opts) do
    with {:ok, context} <- Basic.resolve_context(target, attrs, opts),
         {:ok, scope} <- resolve_scope(target, opts),
         {:ok, extraction} <- extraction_config(opts) do
      {:ok, Map.put(context, :extraction, extraction), scope}
    end
  end

  defp resolve_retrieval_context(target, %Query{} = query, opts) do
    with {:ok, context} <- Basic.resolve_context(target, %{namespace: query.namespace}, opts),
         {:ok, scope} <- resolve_retrieval_scope(target, query, opts),
         {:ok, retrieval} <- retrieval_config(opts, query),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, effective_query} <- attach_namespace(query, context.namespace) do
      {:ok,
       context
       |> Map.put(:scope, scope)
       |> Map.put(:retrieval, retrieval)
       |> Map.put(:effective_query, effective_query)}
    end
  end

  defp normalize_direct_opts(target, opts) when is_list(opts) do
    plugin_state = plugin_state(target)

    if Keyword.has_key?(opts, :provider) or Keyword.has_key?(opts, :provider_opts) do
      with {:ok, provider_ref} <- Jido.Memory.ProviderRef.resolve(%{}, opts, plugin_state),
           true <- provider_ref.module == __MODULE__ || {:error, :invalid_provider},
           runtime_opts <- Jido.Memory.ProviderRef.runtime_opts(provider_ref, opts) do
        {:ok, runtime_opts}
      else
        false -> {:error, :invalid_provider}
        {:error, _reason} = error -> error
      end
    else
      {:ok, opts}
    end
  end

  defp normalize_direct_opts(_target, _opts), do: {:error, :invalid_provider_opts}

  defp normalize_feedback(feedback) when is_atom(feedback) do
    with {:ok, status} <- normalize_feedback_status(feedback) do
      {:ok, %{status: status, note: nil, source: :provider_direct}}
    end
  end

  defp normalize_feedback(feedback) when is_list(feedback), do: normalize_feedback(Map.new(feedback))

  defp normalize_feedback(%{} = feedback) do
    with {:ok, status} <- normalize_feedback_status(value(feedback, :status, value(feedback, :feedback))) do
      {:ok,
       %{
         status: status,
         note: normalize_optional_string_value(value(feedback, :note)),
         source: value(feedback, :source, :provider_direct)
       }}
    end
  end

  defp normalize_feedback(_feedback), do: {:error, :invalid_feedback}

  defp normalize_feedback_status(status) when status in [:useful, :positive], do: {:ok, :useful}
  defp normalize_feedback_status(status) when status in [:not_useful, :negative], do: {:ok, :not_useful}

  defp normalize_feedback_status(status) when is_binary(status) do
    status
    |> String.trim()
    |> String.downcase()
    |> case do
      "useful" -> {:ok, :useful}
      "positive" -> {:ok, :useful}
      "not_useful" -> {:ok, :not_useful}
      "negative" -> {:ok, :not_useful}
      _ -> {:error, :invalid_feedback}
    end
  end

  defp normalize_feedback_status(_status), do: {:error, :invalid_feedback}

  defp persist_feedback(%Record{} = record, context, feedback_attrs) do
    mem0_metadata =
      record.metadata
      |> provider_metadata("mem0")
      |> normalize_metadata()
      |> stringify_map_keys()
      |> Map.put(
        "feedback",
        %{
          "status" => feedback_attrs.status,
          "note" => feedback_attrs.note,
          "source" => feedback_attrs.source,
          "updated_at" => context.now
        }
      )
      |> Map.update("feedback_count", 1, &(&1 + 1))

    updated_record =
      %Record{
        record
        | metadata:
            record.metadata
            |> normalize_metadata()
            |> Map.put("mem0", mem0_metadata)
      }

    context.store_mod.put(updated_record, context.store_opts)
  end

  defp feedback_count(%Record{metadata: metadata}) do
    metadata
    |> provider_metadata("mem0")
    |> map_get("feedback_count") || 0
  end

  defp history_filters(opts) when is_list(opts) do
    with {:ok, event_types} <- normalize_history_event_types(Keyword.get(opts, :event_types, [])),
         {:ok, limit} <- normalize_history_limit(Keyword.get(opts, :limit, 50)) do
      {:ok,
       %{
         record_id: Keyword.get(opts, :record_id),
         fact_key: normalize_optional_string_value(Keyword.get(opts, :fact_key)),
         event_types: event_types,
         limit: limit
       }}
    end
  end

  defp history_records(context, scope, filters) do
    query_limit = min(max(filters.limit * 5, 50), 1_000)

    with {:ok, query} <-
           Query.new(%{
             namespace: history_namespace(context.namespace),
             kinds: [:mem0_history],
             limit: query_limit,
             order: :desc
           }),
         {:ok, records} <- context.store_mod.query(query, context.store_opts) do
      {:ok,
       records
       |> Enum.filter(&scope_matches?(&1, scope))
       |> Enum.filter(&history_record_matches?(&1, filters))
       |> Enum.sort_by(&{&1.observed_at, &1.id}, :desc)
       |> Enum.take(filters.limit)}
    end
  end

  defp history_record_matches?(%Record{} = record, filters) do
    mem0 = record.metadata |> provider_metadata("mem0") |> normalize_metadata() |> stringify_map_keys()

    record_id_match = is_nil(filters.record_id) or Map.get(mem0, "record_id") == filters.record_id
    fact_key_match = is_nil(filters.fact_key) or Map.get(mem0, "fact_key") == filters.fact_key

    event_type_match =
      filters.event_types == [] or
        history_event_type(record) in filters.event_types

    record_id_match and fact_key_match and event_type_match
  end

  defp history_event(%Record{} = record) do
    mem0 = record.metadata |> provider_metadata("mem0") |> normalize_metadata() |> stringify_map_keys()

    %{
      id: record.id,
      event_type: history_event_type(record),
      record_id: Map.get(mem0, "record_id"),
      previous_record_id: Map.get(mem0, "previous_record_id"),
      fact_key: Map.get(mem0, "fact_key"),
      feedback_status: Map.get(mem0, "feedback_status"),
      observed_at: record.observed_at,
      details: Map.get(mem0, "event_details", %{})
    }
  end

  defp history_event_type(%Record{metadata: metadata}) do
    metadata
    |> provider_metadata("mem0")
    |> map_get("event_type")
  end

  defp maybe_log_history_event(context, scope, event_type, details) do
    case build_history_record(context, scope, event_type, details) do
      {:ok, history_record} ->
        case context.store_mod.put(history_record, context.store_opts) do
          {:ok, _record} -> :ok
          {:error, _reason} -> :ok
        end

      {:error, _reason} ->
        :ok
    end
  end

  defp build_history_record(context, scope, event_type, details) do
    mem0_metadata = %{
      event_type: event_type,
      record_id: Map.get(details, :record_id),
      previous_record_id: Map.get(details, :previous_record_id),
      fact_key: Map.get(details, :fact_key),
      feedback_status: Map.get(details, :status),
      event_details: details
    }

    build_record(
      %{
        namespace: history_namespace(context.namespace),
        class: :working,
        kind: :mem0_history,
        text: history_event_text(event_type, details),
        tags: ["mem0", "history", Atom.to_string(event_type)],
        content: stringify_map_keys(Map.new(details))
      },
      history_namespace(context.namespace),
      context.now,
      scope,
      mem0_metadata
    )
  end

  defp history_namespace(namespace), do: "#{namespace}:__mem0_history__"

  defp history_event_text(event_type, details) do
    detail =
      Map.get(details, :record_id) ||
        Map.get(details, :fact_key) ||
        "scoped"

    "mem0:#{event_type}:#{detail}"
  end

  defp history_outcome_event_type(:add), do: :ingest_add
  defp history_outcome_event_type(:update), do: :ingest_update
  defp history_outcome_event_type(:delete), do: :ingest_delete
  defp history_outcome_event_type(:noop), do: :ingest_noop

  defp normalize_history_event_types(event_types) when event_types in [nil, []], do: {:ok, []}

  defp normalize_history_event_types(event_types) when is_list(event_types) do
    event_types
    |> Enum.map(&normalize_history_event_type/1)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, event_type}, {:ok, acc} -> {:cont, {:ok, acc ++ [event_type]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
  end

  defp normalize_history_event_types(event_type),
    do: normalize_history_event_types([event_type])

  defp normalize_history_event_type(event_type)
       when event_type in [:remember, :forget, :feedback, :ingest_add, :ingest_update, :ingest_delete, :ingest_noop],
       do: {:ok, event_type}

  defp normalize_history_event_type(event_type) when is_binary(event_type) do
    event_type
    |> String.trim()
    |> String.downcase()
    |> case do
      "remember" -> {:ok, :remember}
      "forget" -> {:ok, :forget}
      "feedback" -> {:ok, :feedback}
      "ingest_add" -> {:ok, :ingest_add}
      "ingest_update" -> {:ok, :ingest_update}
      "ingest_delete" -> {:ok, :ingest_delete}
      "ingest_noop" -> {:ok, :ingest_noop}
      _ -> {:error, :invalid_history_filter}
    end
  end

  defp normalize_history_event_type(_event_type), do: {:error, :invalid_history_filter}

  defp normalize_history_limit(limit) when is_integer(limit) and limit > 0, do: {:ok, limit}
  defp normalize_history_limit(_limit), do: {:error, :invalid_history_filter}

  defp export_filters(opts) when is_list(opts) do
    with {:ok, limit} <- normalize_history_limit(Keyword.get(opts, :limit, 100)),
         {:ok, history_limit} <- normalize_history_limit(Keyword.get(opts, :history_limit, 50)) do
      {:ok,
       %{
         classes: normalize_filter_list(Keyword.get(opts, :classes, [])),
         kinds: normalize_filter_list(Keyword.get(opts, :kinds, [])),
         limit: limit,
         include_history: Keyword.get(opts, :include_history, false),
         history_limit: history_limit
       }}
    end
  end

  defp export_records(context, scope, filters) do
    with {:ok, query} <-
           Query.new(%{
             namespace: context.namespace,
             classes: filters.classes,
             kinds: filters.kinds,
             limit: min(max(filters.limit * 5, 50), 1_000),
             order: :desc
           }),
         {:ok, records} <- context.store_mod.query(query, context.store_opts) do
      {:ok,
       records
       |> Enum.filter(&scope_matches?(&1, scope))
       |> Enum.filter(&mem0_managed_record?/1)
       |> Enum.take(filters.limit)}
    end
  end

  defp export_record(%Record{} = record) do
    mem0 = record.metadata |> provider_metadata("mem0") |> normalize_metadata() |> stringify_map_keys()

    %{
      id: record.id,
      class: record.class,
      kind: record.kind,
      text: record.text,
      observed_at: record.observed_at,
      fact_key: Map.get(mem0, "fact_key"),
      fact_value: Map.get(mem0, "fact_value"),
      maintenance_action: Map.get(mem0, "maintenance_action"),
      feedback_status: feedback_status(record)
    }
  end

  defp advanced_operations_meta do
    %{
      feedback: %{access: :provider_direct, functions: [:feedback]},
      history: %{access: :provider_direct, functions: [:history]},
      export: %{access: :provider_direct, functions: [:export]},
      maintenance: %{access: :provider_direct, functions: [:refresh_summary, :rerun_reconciliation]}
    }
  end

  defp surface_boundary_meta do
    %{
      shared_runtime: [:remember, :get, :retrieve, :forget, :prune, :capabilities, :info, :explain_retrieval],
      shared_plugin_routes: [:remember, :retrieve, :recall, :forget],
      provider_direct: [:feedback, :history, :export, :refresh_summary, :rerun_reconciliation]
    }
  end

  defp feedback_status(%Record{metadata: metadata}) do
    metadata
    |> provider_metadata("mem0")
    |> map_get("feedback")
    |> normalize_metadata()
    |> map_get("status")
  end

  defp counts_by(records, fun) do
    Enum.reduce(records, %{}, fn record, acc ->
      case fun.(record) do
        nil -> acc
        key -> Map.update(acc, key, 1, &(&1 + 1))
      end
    end)
  end

  defp normalize_filter_list(values) when is_list(values), do: values
  defp normalize_filter_list(nil), do: []
  defp normalize_filter_list(value), do: List.wrap(value)

  defp scoped_identity_meta(opts) do
    with {:ok, defaults} <- normalize_scoped_identity(Keyword.get(opts, :scoped_identity, [])) do
      {:ok,
       %{
         enabled: true,
         source_precedence: @scope_source_precedence,
         supported_dimensions: [:user, :agent, :app, :run],
         defaults: defaults,
         keys: @scope_dimensions
       }}
    end
  end

  defp extraction_context_meta(opts) do
    extraction =
      opts
      |> Keyword.get(:extraction, @default_extraction)
      |> normalize_extraction_config!()

    %{
      supported_payloads: [:messages, :entries],
      recent_window: extraction.recent_window,
      summary_context: extraction.summary_context,
      summary_generation: :provider_owned
    }
  end

  defp retrieval_context_meta(opts) do
    retrieval =
      opts
      |> Keyword.get(:retrieval, @default_retrieval)
      |> normalize_retrieval_config!()

    %{
      default_mode: retrieval.mode,
      graph_augmentation: retrieval.graph_augmentation,
      supported_query_extensions: @supported_mem0_query_extensions
    }
  end

  defp validate_scoped_identity(scoped_identity) do
    case normalize_scoped_identity(scoped_identity) do
      {:ok, _normalized} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp validate_extraction_config(extraction) do
    case normalize_extraction_config(extraction) do
      {:ok, _normalized} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp validate_retrieval_config(retrieval) do
    case normalize_retrieval_config(retrieval) do
      {:ok, _normalized} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp extraction_config(opts) when is_list(opts) do
    provider_opts = normalize_provider_opts(Keyword.get(opts, :provider_opts, []))
    extraction = Keyword.get(provider_opts, :extraction, @default_extraction)
    normalize_extraction_config(extraction)
  end

  defp retrieval_config(opts, %Query{} = query) when is_list(opts) do
    provider_opts = normalize_provider_opts(Keyword.get(opts, :provider_opts, []))

    with {:ok, defaults} <- normalize_retrieval_config(Keyword.get(provider_opts, :retrieval, @default_retrieval)),
         extensions <- mem0_query_extensions(query),
         {:ok, mode} <- normalize_retrieval_mode(value(extensions, :retrieval_mode, defaults.mode)),
         {:ok, graph} <- normalize_graph_hint(value(extensions, :graph, %{}), defaults.graph_augmentation),
         fact_key <- normalize_optional_string_value(value(extensions, :fact_key)),
         {:ok, query_scope} <- normalize_query_scope(value(extensions, :scope, %{})) do
      {:ok,
       %{
         mode: mode,
         fact_key: fact_key,
         graph: graph,
         query_scope: query_scope,
         query_extensions: extensions,
         supported_query_extensions: @supported_mem0_query_extensions
       }}
    end
  end

  defp normalize_retrieval_config(retrieval) when is_list(retrieval) do
    with {:ok, mode} <- normalize_retrieval_mode(Keyword.get(retrieval, :mode, :balanced)),
         {:ok, graph_augmentation} <- normalize_graph_config(Keyword.get(retrieval, :graph_augmentation, [])) do
      {:ok, %{mode: mode, graph_augmentation: graph_augmentation}}
    end
  end

  defp normalize_retrieval_config(_retrieval), do: {:error, :invalid_retrieval_config}

  defp normalize_retrieval_config!(retrieval) do
    case normalize_retrieval_config(retrieval) do
      {:ok, normalized} ->
        normalized

      {:error, _reason} ->
        %{
          mode: :balanced,
          graph_augmentation: %{enabled: false, include_relationships: true, relationship_limit: 5, entity_focus: []}
        }
    end
  end

  defp normalize_retrieval_mode(mode) when mode in [:balanced, :recent_first, :fact_key_first],
    do: {:ok, mode}

  defp normalize_retrieval_mode(mode) when is_binary(mode) do
    mode
    |> String.trim()
    |> String.downcase()
    |> case do
      "balanced" -> {:ok, :balanced}
      "recent_first" -> {:ok, :recent_first}
      "fact_key_first" -> {:ok, :fact_key_first}
      _ -> {:error, :invalid_retrieval_mode}
    end
  end

  defp normalize_retrieval_mode(_mode), do: {:error, :invalid_retrieval_mode}

  defp normalize_extraction_config(extraction) when is_list(extraction) do
    recent_window = Keyword.get(extraction, :recent_window, Keyword.get(@default_extraction, :recent_window))
    summary_context = Keyword.get(extraction, :summary_context, Keyword.get(@default_extraction, :summary_context))

    cond do
      not (is_integer(recent_window) and recent_window > 0) ->
        {:error, :invalid_extraction_config}

      summary_context not in [:optional, :disabled, :required] ->
        {:error, :invalid_extraction_config}

      true ->
        {:ok, %{recent_window: recent_window, summary_context: summary_context}}
    end
  end

  defp normalize_extraction_config(_extraction), do: {:error, :invalid_extraction_config}

  defp normalize_extraction_config!(extraction) do
    case normalize_extraction_config(extraction) do
      {:ok, normalized} -> normalized
      {:error, _reason} -> %{recent_window: 6, summary_context: :optional}
    end
  end

  defp normalize_scoped_identity(scoped_identity) when scoped_identity in [%{}, []], do: {:ok, empty_scope()}

  defp normalize_scoped_identity(scoped_identity) when is_list(scoped_identity) do
    scoped_identity
    |> Enum.into(%{})
    |> normalize_scoped_identity()
  rescue
    ArgumentError -> {:error, :invalid_scoped_identity}
  end

  defp normalize_scoped_identity(%{} = scoped_identity) do
    Enum.reduce_while(@scope_dimensions, {:ok, empty_scope()}, fn dimension, {:ok, acc} ->
      case normalize_scope_value(provider_scope_value(scoped_identity, dimension)) do
        {:ok, normalized} -> {:cont, {:ok, Map.put(acc, dimension, normalized)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_scoped_identity(_scoped_identity), do: {:error, :invalid_scoped_identity}

  defp normalize_query_scope(scope) when scope in [%{}, []], do: {:ok, empty_scope()}
  defp normalize_query_scope(scope), do: normalize_scoped_identity(scope)

  defp resolve_scope_value(dimension, target, opts, defaults) do
    normalize_scope_value!(
      pick_runtime_scope(opts, dimension) ||
        pick_target_scope(target, dimension) ||
        Map.get(defaults, dimension)
    )
  end

  defp resolve_retrieval_scope(target, %Query{} = query, opts) do
    provider_opts = normalize_provider_opts(Keyword.get(opts, :provider_opts, []))

    with {:ok, defaults} <- normalize_scoped_identity(Keyword.get(provider_opts, :scoped_identity, [])),
         {:ok, retrieval} <- retrieval_config(opts, query) do
      {:ok,
       Enum.reduce(@scope_dimensions, %{}, fn dimension, acc ->
         Map.put(
           acc,
           dimension,
           resolve_retrieval_scope_value(dimension, target, opts, retrieval.query_scope, defaults)
         )
       end)}
    end
  end

  defp resolve_retrieval_scope_value(dimension, target, opts, query_scope, defaults) do
    normalize_scope_value!(
      pick_runtime_scope(opts, dimension) ||
        Map.get(query_scope, dimension) ||
        pick_target_scope(target, dimension) ||
        Map.get(defaults, dimension)
    )
  end

  defp pick_runtime_scope(opts, dimension) when is_list(opts) do
    Keyword.get(opts, dimension)
  end

  defp pick_target_scope(target, dimension) do
    explicit =
      map_get(target, dimension) ||
        map_get(target, normalize_dimension_alias(dimension))

    case {dimension, explicit} do
      {:agent_id, nil} -> map_get(target, :id)
      _ -> explicit
    end
  end

  defp provider_scope_value(scoped_identity, dimension) do
    map_get(scoped_identity, dimension) ||
      map_get(scoped_identity, normalize_dimension_alias(dimension))
  end

  defp normalize_dimension_alias(:user_id), do: :user
  defp normalize_dimension_alias(:agent_id), do: :agent
  defp normalize_dimension_alias(:app_id), do: :app
  defp normalize_dimension_alias(:run_id), do: :run

  defp build_record(attrs, namespace, now, scope, mem0_metadata) do
    attrs =
      attrs
      |> Map.drop([:provider, "provider"])
      |> Map.put(:namespace, namespace)
      |> Map.put_new(:observed_at, now)
      |> Map.update(
        :metadata,
        annotate_mem0_metadata(%{}, scope, mem0_metadata),
        &annotate_mem0_metadata(&1, scope, mem0_metadata)
      )

    Record.new(attrs, now: now)
  end

  defp build_query(attrs, namespace) do
    attrs =
      attrs
      |> Map.drop([:provider, "provider"])
      |> then(fn normalized ->
        if is_binary(namespace), do: Map.put_new(normalized, :namespace, namespace), else: normalized
      end)

    Query.new(attrs)
  end

  defp attach_namespace(%Query{namespace: nil} = query, namespace) when is_binary(namespace),
    do: {:ok, %{query | namespace: namespace}}

  defp attach_namespace(%Query{namespace: query_namespace} = query, runtime_namespace)
       when is_binary(query_namespace) and is_binary(runtime_namespace),
       do: {:ok, query}

  defp attach_namespace(%Query{}, _namespace), do: {:error, :namespace_required}

  defp annotate_mem0_metadata(metadata, scope, extra_mem0) do
    mem0 =
      metadata
      |> Map.get("mem0", %{})
      |> normalize_metadata()
      |> stringify_map_keys()
      |> Map.merge(stringify_map_keys(normalize_metadata(extra_mem0)))
      |> Map.put("scope", scope_to_metadata(scope))
      |> Map.put_new("source_provider", "mem0")

    Map.put(metadata, "mem0", mem0)
  end

  defp normalize_ingest_payload(%{} = payload, extraction_config) do
    with {:ok, summary} <- normalize_summary_context(payload, extraction_config),
         {:ok, entries} <- normalize_ingest_entries(payload, extraction_config) do
      {:ok, %{entries: entries, summary: summary}}
    end
  end

  defp normalize_summary_context(payload, extraction_config) do
    summary = normalize_optional_string_value(value(payload, :summary))

    case {summary, extraction_config.summary_context} do
      {nil, :required} -> {:error, :missing_summary_context}
      {summary, _mode} -> {:ok, summary}
    end
  end

  defp normalize_ingest_entries(payload, extraction_config) do
    entries = value(payload, :entries)
    messages = value(payload, :messages)

    cond do
      is_list(entries) and entries != [] ->
        payload
        |> value(:entries)
        |> Enum.map(&normalize_ingest_entry(&1, :entries))
        |> then(&normalize_ingest_entry_results(&1))

      is_list(messages) and messages != [] ->
        payload
        |> value(:messages)
        |> Enum.take(-extraction_config.recent_window)
        |> Enum.map(&normalize_ingest_entry(&1, :messages))
        |> then(&normalize_ingest_entry_results(&1))

      true ->
        {:error, :invalid_ingest_payload}
    end
  end

  defp normalize_ingest_entry_results(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, entry}, {:ok, acc} -> {:cont, {:ok, acc ++ [entry]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
  end

  defp normalize_ingest_entry(%{} = entry, origin) do
    {:ok,
     %{
       role: normalize_role(value(entry, :role, :user)),
       content: normalize_entry_content(value(entry, :content, value(entry, :text))),
       metadata: normalize_metadata(value(entry, :metadata, %{})),
       source: value(entry, :source),
       observed_at: value(entry, :observed_at),
       origin: origin
     }}
  end

  defp normalize_ingest_entry(_entry, _origin), do: {:error, :invalid_ingest_payload}

  defp do_retrieve_records(%Query{} = query, context) do
    fetch_query = %{context.effective_query | limit: retrieval_fetch_limit(query.limit)}

    with {:ok, records} <- context.store_mod.query(fetch_query, context.store_opts) do
      {:ok,
       records
       |> Enum.filter(&scope_matches?(&1, context.scope))
       |> rank_retrieval_results(query, context.retrieval)
       |> Enum.take(query.limit)}
    end
  end

  defp retrieval_fetch_limit(limit) when is_integer(limit) and limit > 0,
    do: min(max(limit * 5, 50), 1000)

  defp rank_retrieval_results(records, %Query{} = query, retrieval) do
    records
    |> Enum.sort_by(&retrieval_sort_key(&1, query, retrieval), :desc)
  end

  defp retrieval_sort_key(%Record{} = record, %Query{} = query, retrieval) do
    {
      retrieval_mode_score(record, query, retrieval),
      maintenance_priority(record),
      recency_priority(record, query.order),
      record.id
    }
  end

  defp retrieval_mode_score(_record, _query, %{mode: :recent_first}), do: 0

  defp retrieval_mode_score(record, _query, %{mode: :fact_key_first, fact_key: fact_key}) do
    if fact_key(record) == fact_key or fact_key_text_match?(record, fact_key), do: 2, else: 0
  end

  defp retrieval_mode_score(record, %Query{} = query, %{mode: :balanced, fact_key: fact_key}) do
    score =
      if fact_key(record) == fact_key or fact_key_text_match?(record, fact_key), do: 2, else: 0

    if query_text_match?(record, query.text_contains), do: score + 1, else: score
  end

  defp recency_priority(%Record{observed_at: observed_at}, :asc), do: -observed_at
  defp recency_priority(%Record{observed_at: observed_at}, _order), do: observed_at

  defp maintenance_priority(%Record{metadata: metadata}) do
    case get_in(metadata, ["mem0", "maintenance_action"]) do
      :update -> 3
      :add -> 2
      :noop -> 1
      _ -> 0
    end
  end

  defp fact_key_text_match?(_record, nil), do: false
  defp fact_key_text_match?(%Record{text: text}, fact_key) when is_binary(text), do: String.starts_with?(text, fact_key)
  defp fact_key_text_match?(_record, _fact_key), do: false

  defp query_text_match?(_record, nil), do: false

  defp query_text_match?(%Record{text: text, content: content}, filter) do
    candidate_text =
      [text, inspect(content)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(candidate_text, String.downcase(filter))
  end

  defp mem0_query_extensions(%Query{} = query) do
    query
    |> Query.extensions()
    |> value(:mem0, %{})
    |> normalize_metadata()
  end

  defp normalize_graph_config(graph_augmentation) when graph_augmentation in [nil, [], %{}] do
    {:ok, %{enabled: false, include_relationships: true, relationship_limit: 5, entity_focus: []}}
  end

  defp normalize_graph_config(graph_augmentation) when is_list(graph_augmentation) do
    graph_augmentation
    |> Enum.into(%{})
    |> normalize_graph_config()
  rescue
    ArgumentError -> {:error, :invalid_retrieval_config}
  end

  defp normalize_graph_config(%{} = graph_augmentation) do
    enabled = value(graph_augmentation, :enabled, false)
    include_relationships = value(graph_augmentation, :include_relationships, true)
    relationship_limit = value(graph_augmentation, :relationship_limit, 5)
    entity_focus = normalize_graph_entity_focus(value(graph_augmentation, :entity_focus, []))

    cond do
      not is_boolean(enabled) ->
        {:error, :invalid_retrieval_config}

      not is_boolean(include_relationships) ->
        {:error, :invalid_retrieval_config}

      not (is_integer(relationship_limit) and relationship_limit > 0) ->
        {:error, :invalid_retrieval_config}

      true ->
        {:ok,
         %{
           enabled: enabled,
           include_relationships: include_relationships,
           relationship_limit: relationship_limit,
           entity_focus: entity_focus
         }}
    end
  end

  defp normalize_graph_config(_graph_augmentation), do: {:error, :invalid_retrieval_config}

  defp normalize_graph_hint(graph_hint, defaults) when graph_hint in [nil, [], %{}] do
    {:ok, Map.put(defaults, :source, if(defaults.enabled, do: :provider_config, else: :disabled))}
  end

  defp normalize_graph_hint(true, defaults),
    do: {:ok, defaults |> Map.merge(%{enabled: true}) |> Map.put(:source, :query_extension)}

  defp normalize_graph_hint(false, defaults),
    do: {:ok, defaults |> Map.merge(%{enabled: false}) |> Map.put(:source, :query_extension)}

  defp normalize_graph_hint(graph_hint, defaults) when is_list(graph_hint) do
    graph_hint
    |> Enum.into(%{})
    |> normalize_graph_hint(defaults)
  rescue
    ArgumentError -> {:error, :invalid_query}
  end

  defp normalize_graph_hint(%{} = graph_hint, defaults) do
    with {:ok, normalized} <- normalize_graph_config(graph_hint) do
      {:ok,
       defaults
       |> Map.merge(normalized)
       |> Map.put(:source, :query_extension)}
    end
  end

  defp normalize_graph_hint(_graph_hint, _defaults), do: {:error, :invalid_query}

  defp build_explanation(%Query{} = query, context, records) do
    result_entries =
      records
      |> Enum.with_index(1)
      |> Enum.map(fn {record, rank} ->
        explain_result_entry(record, rank, query, context)
      end)

    %{
      provider: __MODULE__,
      namespace: context.namespace,
      query: summarize_query(query),
      result_count: length(result_entries),
      results: result_entries,
      extensions: %{
        mem0: %{
          payload_version: 1,
          scope: %{
            effective: context.scope,
            query: context.retrieval.query_scope
          },
          retrieval_strategy: %{
            mode: context.retrieval.mode,
            fact_key: context.retrieval.fact_key,
            query_extensions: context.retrieval.query_extensions,
            supported_query_extensions: @supported_mem0_query_extensions
          },
          graph: graph_context(records, query, context.retrieval),
          reconciliation: %{
            maintenance_actions_present: maintenance_actions_present(records),
            results_with_maintenance: Enum.count(records, &(maintenance_action(&1) != nil)),
            ranking_signals: [:retrieval_mode, :maintenance_action, :recency]
          },
          notes: reconciliation_notes(records)
        }
      }
    }
  end

  defp explain_result_entry(%Record{} = record, rank, %Query{} = query, context) do
    %{
      id: record.id,
      rank: rank,
      matched_on: matched_on(record, query, context.retrieval),
      ranking_context: %{
        mode: context.retrieval.mode,
        fact_key_match: fact_key_match?(record, context.retrieval.fact_key),
        maintenance_action: maintenance_action(record),
        observed_at: record.observed_at
      }
    }
  end

  defp summarize_query(%Query{} = query) do
    %{
      namespace: query.namespace,
      classes: query.classes,
      kinds: query.kinds,
      tags_any: query.tags_any,
      tags_all: query.tags_all,
      text_contains: query.text_contains,
      since: query.since,
      until: query.until,
      limit: query.limit,
      order: query.order,
      extensions: query.extensions
    }
  end

  defp matched_on(%Record{} = record, %Query{} = query, retrieval) do
    []
    |> maybe_add_match(query.classes != [], :class)
    |> maybe_add_match(query.kinds != [], :kind)
    |> maybe_add_match(query.tags_any != [], :tags_any)
    |> maybe_add_match(query.tags_all != [], :tags_all)
    |> maybe_add_match(
      is_binary(query.text_contains) and query_text_match?(record, query.text_contains),
      :text_contains
    )
    |> maybe_add_match(is_integer(query.since), :since)
    |> maybe_add_match(is_integer(query.until), :until)
    |> maybe_add_match(fact_key_match?(record, retrieval.fact_key), :fact_key)
    |> case do
      [] -> [:scope]
      matches -> matches
    end
  end

  defp maybe_add_match(matches, true, match), do: matches ++ [match]
  defp maybe_add_match(matches, false, _match), do: matches

  defp fact_key_match?(%Record{} = record, fact_key) do
    fact_key(record) == fact_key or fact_key_text_match?(record, fact_key)
  end

  defp maintenance_action(%Record{metadata: metadata}) do
    get_in(metadata, ["mem0", "maintenance_action"])
  end

  defp maintenance_actions_present(records) do
    records
    |> Enum.map(&maintenance_action/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp reconciliation_notes(records) do
    case maintenance_actions_present(records) do
      [] -> [:canonical_retrieval]
      actions -> [:reconciliation_aware_retrieval | Enum.map(actions, &{:maintenance_action, &1})]
    end
  end

  defp graph_context(records, %Query{} = query, retrieval) do
    if retrieval.graph.enabled do
      focus_terms = graph_focus_terms(query, retrieval)
      entities = graph_entities(records, focus_terms)
      relationships = graph_relationships(records, focus_terms, retrieval.graph)

      %{
        enabled: true,
        source: retrieval.graph.source,
        entity_focus: focus_terms,
        entity_count: length(entities),
        relationship_count: length(relationships),
        entities: entities,
        relationships: relationships
      }
    else
      %{
        enabled: false,
        source: retrieval.graph.source,
        entity_focus: [],
        entity_count: 0,
        relationship_count: 0,
        entities: [],
        relationships: []
      }
    end
  end

  defp graph_focus_terms(%Query{} = query, retrieval) do
    retrieval.graph.entity_focus
    |> Kernel.++(Enum.filter([retrieval.fact_key, query.text_contains], &is_binary/1))
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  defp graph_entities(records, focus_terms) do
    records
    |> Enum.flat_map(&record_graph_entities(&1, focus_terms))
    |> Enum.uniq_by(& &1.id)
  end

  defp record_graph_entities(%Record{} = record, focus_terms) do
    [
      graph_entity("fact_key", fact_key(record), :fact_key, record.id, focus_terms),
      graph_entity("fact_value", fact_value(record), :fact_value, record.id, focus_terms)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp graph_entity(_prefix, nil, _type, _record_id, _focus_terms), do: nil

  defp graph_entity(prefix, value, type, record_id, focus_terms) do
    label = to_string(value)

    if focus_terms == [] or Enum.any?(focus_terms, &String.contains?(String.downcase(label), &1)) do
      %{id: "#{prefix}:#{label}", label: label, type: type, record_id: record_id}
    end
  end

  defp graph_relationships(_records, _focus_terms, %{include_relationships: false}), do: []

  defp graph_relationships(records, focus_terms, %{relationship_limit: relationship_limit}) do
    records
    |> Enum.flat_map(&record_graph_relationships(&1, focus_terms))
    |> Enum.take(relationship_limit)
  end

  defp record_graph_relationships(%Record{} = record, focus_terms) do
    case {fact_key(record), fact_value(record)} do
      {nil, _value} ->
        []

      {_key, nil} ->
        []

      {key, value} ->
        labels = [to_string(key), to_string(value)] |> Enum.map(&String.downcase/1)

        if graph_relationship_matches?(labels, focus_terms) do
          [
            %{
              source: to_string(key),
              predicate: :value,
              target: to_string(value),
              record_id: record.id
            }
          ]
        else
          []
        end
    end
  end

  defp graph_relationship_matches?(_labels, []), do: true

  defp graph_relationship_matches?(labels, focus_terms) do
    Enum.any?(focus_terms, fn term ->
      Enum.any?(labels, &String.contains?(&1, term))
    end)
  end

  defp normalize_graph_entity_focus(values) when is_list(values) do
    values
    |> Enum.map(&normalize_optional_string_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_graph_entity_focus(value) do
    value
    |> List.wrap()
    |> normalize_graph_entity_focus()
  end

  defp extract_candidates(%{entries: entries, summary: summary}, extraction_config) do
    result =
      Enum.reduce(entries, %{candidates: [], skipped: []}, fn entry, acc ->
        {candidates, skipped} = extract_entry_candidates(entry, summary, extraction_config)
        %{candidates: acc.candidates ++ candidates, skipped: acc.skipped ++ skipped}
      end)

    {:ok, result}
  end

  defp extract_entry_candidates(%{role: role} = entry, _summary, _extraction_config)
       when role in [:assistant, "assistant"] do
    {[],
     [
       %{
         reason: :unsupported_role,
         role: role,
         content: entry.content,
         origin: entry.origin
       }
     ]}
  end

  defp extract_entry_candidates(entry, summary, extraction_config) do
    sentences = candidate_sentences(entry.content)

    result =
      Enum.reduce(sentences, %{candidates: [], skipped: []}, fn sentence, acc ->
        case candidate_from_sentence(sentence, entry, summary, extraction_config) do
          {:ok, candidate} ->
            %{acc | candidates: acc.candidates ++ [candidate]}

          {:skip, reason} ->
            %{acc | skipped: acc.skipped ++ [%{reason: reason, content: sentence, origin: entry.origin}]}
        end
      end)

    result =
      if result.candidates == [] and result.skipped == [] do
        %{result | skipped: [%{reason: :no_candidate, content: entry.content, origin: entry.origin}]}
      else
        result
      end

    {result.candidates, result.skipped}
  end

  defp candidate_from_sentence(sentence, entry, summary, extraction_config) do
    case parse_candidate_sentence(sentence) do
      {:ok, pattern, captures} ->
        {:ok, build_candidate(pattern, captures, sentence, entry, summary, extraction_config)}

      :error ->
        {:skip, :no_candidate}
    end
  end

  defp parse_candidate_sentence(sentence) do
    patterns = [
      {:favorite_delete, ~r/^forget that my favorite (?<slot>[\w\s-]+) is (?<value>[^.?!]+)$/i},
      {:favorite_set, ~r/^my favorite (?<slot>[\w\s-]+) is (?<value>[^.?!]+)$/i},
      {:location_delete, ~r/^i no longer live in (?<value>[^.?!]+)$/i},
      {:location_set, ~r/^i live in (?<value>[^.?!]+)$/i},
      {:tool_delete, ~r/^i no longer use (?<value>[^.?!]+) for (?<slot>[^.?!]+)$/i},
      {:tool_set, ~r/^i use (?<value>[^.?!]+) for (?<slot>[^.?!]+)$/i},
      {:preference_set, ~r/^i prefer (?<value>[^.?!]+) for (?<slot>[^.?!]+)$/i},
      {:name_set, ~r/^call me (?<value>[^.?!]+)$/i},
      {:name_set, ~r/^my name is (?<value>[^.?!]+)$/i},
      {:project_set, ~r/^i work on (?<value>[^.?!]+)$/i}
    ]

    Enum.find_value(patterns, :error, fn {pattern_name, regex} ->
      case Regex.named_captures(regex, sentence) do
        %{} = captures -> {:ok, pattern_name, captures}
        _ -> false
      end
    end)
  end

  defp build_candidate(pattern, captures, sentence, entry, summary, extraction_config) do
    base =
      %{
        role: entry.role,
        origin: entry.origin,
        source: entry.source,
        observed_at: entry.observed_at,
        summary_used: is_binary(summary) and extraction_config.summary_context != :disabled,
        source_excerpt: sentence,
        pattern: pattern
      }

    {action, fact_key, fact_value, tag_label} = candidate_definition(pattern, captures)
    build_fact_candidate(base, action, fact_key, fact_value, tag_label, sentence)
  end

  defp candidate_definition(pattern, captures) when pattern in [:favorite_set, :favorite_delete] do
    slot = normalize_fact_fragment(Map.fetch!(captures, "slot"))
    value = normalize_fact_fragment(Map.fetch!(captures, "value"))
    action = if pattern == :favorite_set, do: :upsert, else: :delete
    {action, "favorite:#{slot}", value, "favorite #{slot}"}
  end

  defp candidate_definition(pattern, captures) when pattern in [:location_set, :location_delete] do
    value = normalize_fact_fragment(Map.fetch!(captures, "value"))
    action = if pattern == :location_set, do: :upsert, else: :delete
    {action, "location:home", value, "location home"}
  end

  defp candidate_definition(pattern, captures) when pattern in [:tool_set, :tool_delete] do
    slot = normalize_fact_fragment(Map.fetch!(captures, "slot"))
    value = normalize_fact_fragment(Map.fetch!(captures, "value"))
    action = if pattern == :tool_set, do: :upsert, else: :delete
    {action, "tool:#{slot}", value, "tool #{slot}"}
  end

  defp candidate_definition(:preference_set, captures) do
    slot = normalize_fact_fragment(Map.fetch!(captures, "slot"))
    value = normalize_fact_fragment(Map.fetch!(captures, "value"))
    {:upsert, "preference:#{slot}", value, "preference #{slot}"}
  end

  defp candidate_definition(:name_set, captures) do
    value = normalize_fact_fragment(Map.fetch!(captures, "value"))
    {:upsert, "identity:name", value, "identity name"}
  end

  defp candidate_definition(:project_set, captures) do
    value = normalize_fact_fragment(Map.fetch!(captures, "value"))
    {:upsert, "work:project", value, "work project"}
  end

  defp build_fact_candidate(base, action, fact_key, fact_value, tag_label, sentence) do
    %{
      action: action,
      class: :semantic,
      kind: :fact,
      fact_key: fact_key,
      fact_value: fact_value,
      text: canonical_fact_text(fact_key, fact_value),
      tags: ["mem0", "fact", normalize_fact_fragment(tag_label)],
      content: %{fact_key: fact_key, fact_value: fact_value, source_excerpt: sentence},
      metadata: %{
        fact_key: fact_key,
        fact_value: fact_value,
        extraction: %{
          pattern: base.pattern,
          role: to_string(base.role),
          origin: Atom.to_string(base.origin),
          summary_used: base.summary_used
        }
      },
      source: base.source,
      observed_at: base.observed_at
    }
  end

  defp persist_extracted_candidates(extracted, context, scope, normalized_payload) do
    result =
      Enum.reduce(extracted.candidates, initial_ingest_summary(context, normalized_payload), fn candidate, acc ->
        case reconcile_candidate(candidate, context, scope) do
          {:ok, outcome, details} ->
            maybe_log_history_event(context, scope, history_outcome_event_type(outcome), %{
              record_id: details.record_id,
              previous_record_id: Map.get(details, :previous_record_id),
              fact_key: details.fact_key,
              write_mode: :ingest,
              summary_present: is_binary(normalized_payload.summary)
            })

            acc
            |> track_maintenance_outcome(outcome, details)
            |> Map.update!(:extracted_candidates, &(&1 ++ [candidate_summary(candidate)]))

          {:error, reason} ->
            Map.update!(acc, :skipped_candidates, &(&1 ++ [%{reason: reason, fact_key: candidate.fact_key}]))
        end
      end)

    {:ok, %{result | skipped_candidates: result.skipped_candidates ++ extracted.skipped}}
  end

  defp reconcile_candidate(candidate, context, scope) do
    similar_records = similar_records_for_candidate(candidate, context, scope)

    case candidate.action do
      :upsert -> reconcile_upsert_candidate(candidate, context, scope, similar_records)
      :delete -> reconcile_delete_candidate(candidate, context, similar_records)
    end
  end

  defp reconcile_upsert_candidate(candidate, context, scope, similar_records) do
    exact_match =
      Enum.find(similar_records, fn record ->
        fact_value(record) == candidate.fact_value
      end)

    case {similar_records, exact_match} do
      {[], nil} ->
        with {:ok, record} <- persist_candidate_record(candidate, context, scope, :add, nil, similar_records) do
          {:ok, :add, %{record_id: record.id, fact_key: candidate.fact_key}}
        end

      {_records, %Record{} = record} ->
        {:ok, :noop, %{record_id: record.id, fact_key: candidate.fact_key}}

      {[existing | _], nil} ->
        with {:ok, record} <- persist_candidate_record(candidate, context, scope, :update, existing, similar_records) do
          {:ok, :update,
           %{
             record_id: record.id,
             previous_record_id: existing.id,
             fact_key: candidate.fact_key
           }}
        end
    end
  end

  defp reconcile_delete_candidate(candidate, context, similar_records) do
    case matching_record_for_delete(similar_records, candidate.fact_value) do
      nil ->
        {:ok, :noop, %{record_id: nil, fact_key: candidate.fact_key}}

      %Record{} = record ->
        :ok = context.store_mod.delete({record.namespace, record.id}, context.store_opts)
        {:ok, :delete, %{record_id: record.id, fact_key: candidate.fact_key}}
    end
  end

  defp persist_candidate_record(candidate, context, scope, action, existing_record, similar_records) do
    mem0_metadata =
      candidate.metadata
      |> Map.put(:write_mode, :ingest)
      |> Map.put(:maintenance_action, action)
      |> Map.put(:similar_record_ids, Enum.map(similar_records, & &1.id))
      |> maybe_put(:previous_record_id, existing_record && existing_record.id)
      |> maybe_put(:previous_fact_value, existing_record && fact_value(existing_record))

    attrs =
      %{
        class: candidate.class,
        kind: candidate.kind,
        text: candidate.text,
        tags: candidate.tags,
        content: candidate.content,
        source: candidate.source,
        observed_at: candidate.observed_at,
        metadata: candidate.metadata
      }
      |> maybe_put(:id, existing_record && existing_record.id)

    with {:ok, record} <- build_record(attrs, context.namespace, context.now, scope, mem0_metadata) do
      context.store_mod.put(record, context.store_opts)
    end
  end

  defp similar_records_for_candidate(candidate, context, scope) do
    with {:ok, query} <- Query.new(%{namespace: context.namespace, classes: [:semantic], limit: 1000, order: :desc}),
         {:ok, records} <- context.store_mod.query(query, context.store_opts) do
      records
      |> Enum.filter(&relevant_candidate_record?(&1, candidate, scope))
      |> Enum.sort_by(& &1.observed_at, :desc)
    else
      _ -> []
    end
  end

  defp relevant_candidate_record?(%Record{} = record, candidate, scope) do
    scope_matches?(record, scope) and
      mem0_managed_record?(record) and
      similar_candidate_record?(record, candidate)
  end

  defp mem0_managed_record?(%Record{metadata: metadata}) do
    metadata
    |> provider_metadata("mem0")
    |> normalize_metadata()
    |> map_size() > 0
  end

  defp similar_candidate_record?(%Record{} = record, candidate) do
    record_fact_key = fact_key(record)
    record_text = normalize_fact_fragment(record.text || "")
    candidate_text = normalize_fact_fragment(candidate.text)

    record_fact_key == candidate.fact_key or
      record_text == candidate_text or
      String.starts_with?(record_text, "#{candidate.fact_key}=")
  end

  defp matching_record_for_delete(similar_records, candidate_value) do
    Enum.find(similar_records, fn record ->
      fact_value(record) == candidate_value
    end) || List.first(similar_records)
  end

  defp initial_ingest_summary(context, normalized_payload) do
    %{
      provider: __MODULE__,
      extraction_context: %{
        recent_window: context.extraction.recent_window,
        summary_context: context.extraction.summary_context,
        summary_present: is_binary(normalized_payload.summary)
      },
      extracted_candidates: [],
      skipped_candidates: [],
      created_ids: [],
      updated_ids: [],
      deleted_ids: [],
      noop_ids: [],
      maintenance_results: [],
      maintenance: %{add: 0, update: 0, delete: 0, noop: 0}
    }
  end

  defp candidate_summary(candidate) do
    %{
      action: candidate.action,
      fact_key: candidate.fact_key,
      fact_value: candidate.fact_value,
      text: candidate.text
    }
  end

  defp increment_maintenance(summary, key) do
    update_in(summary, [:maintenance, key], &(&1 + 1))
  end

  defp track_maintenance_outcome(summary, outcome, details) do
    summary
    |> maybe_track_outcome_id(outcome, details)
    |> Map.update!(:maintenance_results, &(&1 ++ [Map.put(details, :outcome, outcome)]))
    |> increment_maintenance(outcome)
  end

  defp maybe_track_outcome_id(summary, :add, %{record_id: record_id}),
    do: Map.update!(summary, :created_ids, &(&1 ++ [record_id]))

  defp maybe_track_outcome_id(summary, :update, %{record_id: record_id}),
    do: Map.update!(summary, :updated_ids, &(&1 ++ [record_id]))

  defp maybe_track_outcome_id(summary, :delete, %{record_id: record_id}),
    do: Map.update!(summary, :deleted_ids, &(&1 ++ [record_id]))

  defp maybe_track_outcome_id(summary, :noop, %{record_id: record_id}),
    do: Map.update!(summary, :noop_ids, &(&1 ++ if(is_nil(record_id), do: [], else: [record_id])))

  defp fact_key(%Record{metadata: metadata}) do
    metadata
    |> provider_metadata("mem0")
    |> map_get("fact_key")
  end

  defp fact_value(%Record{metadata: metadata}) do
    metadata
    |> provider_metadata("mem0")
    |> map_get("fact_value")
  end

  defp candidate_sentences(nil), do: []

  defp candidate_sentences(content) when is_binary(content) do
    content
    |> String.split(~r/[.!?\n]+/u, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp candidate_sentences(other), do: candidate_sentences(inspect(other))

  defp normalize_role(role) when is_atom(role), do: role
  defp normalize_role(role) when is_binary(role), do: String.downcase(String.trim(role))
  defp normalize_role(_role), do: :user

  defp normalize_entry_content(nil), do: nil
  defp normalize_entry_content(content) when is_binary(content), do: content
  defp normalize_entry_content(content), do: inspect(content)

  defp normalize_fact_fragment(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
  end

  defp canonical_fact_text(fact_key, fact_value) do
    "#{fact_key}=#{fact_value}"
  end

  defp normalize_optional_string_value(nil), do: nil

  defp normalize_optional_string_value(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_optional_string_value(value), do: inspect(value)

  defp maybe_forget_scoped_record(record, context, scope, id) do
    if scope_matches?(record, scope) do
      :ok = context.store_mod.delete({context.namespace, id}, context.store_opts)

      maybe_log_history_event(context, scope, :forget, %{record_id: id, fact_key: fact_key(record), write_mode: :direct})

      {:ok, true}
    else
      {:ok, false}
    end
  end

  defp scope_matches?(%Record{metadata: metadata}, effective_scope) when is_map(effective_scope) do
    record_scope =
      metadata
      |> provider_metadata("mem0")
      |> map_get("scope")
      |> normalize_metadata()
      |> stringify_map_keys()

    Enum.all?(@scope_dimensions, fn dimension ->
      case Map.get(effective_scope, dimension) do
        nil -> true
        expected -> Map.get(record_scope, Atom.to_string(dimension)) == expected
      end
    end)
  end

  defp scope_to_metadata(scope) when is_map(scope) do
    scope
    |> Enum.reduce(%{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, Atom.to_string(key), value)
    end)
  end

  defp normalize_scope_value(nil), do: {:ok, nil}

  defp normalize_scope_value(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: {:ok, nil}, else: {:ok, trimmed}
  end

  defp normalize_scope_value(value) when is_atom(value), do: {:ok, Atom.to_string(value)}
  defp normalize_scope_value(_value), do: {:error, :invalid_scoped_identity}

  defp normalize_scope_value!(value) do
    case normalize_scope_value(value) do
      {:ok, normalized} -> normalized
      {:error, _reason} -> nil
    end
  end

  defp empty_scope do
    %{user_id: nil, agent_id: nil, app_id: nil, run_id: nil}
  end

  defp normalize_provider_opts(opts) when is_list(opts), do: opts
  defp normalize_provider_opts(_opts), do: []

  defp normalize_metadata(%{} = metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}

  defp provider_metadata(metadata, key) when is_map(metadata) do
    case key do
      "mem0" -> Map.get(metadata, "mem0", Map.get(metadata, :mem0, %{}))
      _ -> Map.get(metadata, key, %{})
    end
  end

  defp provider_metadata(_metadata, _key), do: %{}

  defp stringify_map_keys(%{} = map) do
    Enum.into(map, %{}, fn {key, value} ->
      {stringify_key(key), value}
    end)
  end

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: key

  defp map_get(%{} = map, key) when is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp map_get(%{} = map, key) when is_binary(key),
    do: Map.get(map, key)

  defp map_get(_value, _key), do: nil

  defp value(map, key, default \\ nil) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp plugin_state(%{state: %{} = state}),
    do: Map.get(state, Jido.Memory.Runtime.plugin_state_key(), %{}) |> normalize_metadata()

  defp plugin_state(%{} = map),
    do: Map.get(map, Jido.Memory.Runtime.plugin_state_key(), %{}) |> normalize_metadata()

  defp plugin_state(_target), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
