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

  alias Jido.Memory.ProviderRef
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.{Query, Record, Store}

  @default_extraction [recent_window: 6, summary_context: :optional]
  @scope_dimensions [:user_id, :agent_id, :app_id, :run_id]
  @scope_source_precedence [:runtime_opts, :target, :provider_config]

  @capabilities %{
    core: true,
    retrieval: %{
      explainable: false,
      active: false,
      memory_types: false,
      provider_extensions: true,
      scoped: true,
      graph_augmentation: false
    },
    lifecycle: %{consolidate: false, inspect: false},
    ingestion: %{batch: true, multimodal: false, routed: true, access: :provider_direct},
    operations: %{feedback: :provider_direct, export: :provider_direct, history: :provider_direct},
    governance: %{protected_memory: false, exact_preservation: false, access: :none},
    hooks: %{}
  }

  @impl true
  def validate_config(opts) when is_list(opts) do
    with :ok <- Basic.validate_config(opts) do
      with :ok <- validate_scoped_identity(Keyword.get(opts, :scoped_identity, [])) do
        validate_extraction_config(Keyword.get(opts, :extraction, @default_extraction))
      end
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
         retrieval: %{scoped: true, explainable: false, graph_augmentation: false},
         maintenance: %{
           reconciliation: :provider_direct,
           feedback: :provider_direct,
           history: :provider_direct,
           outcomes: [:add, :update, :delete, :noop],
           similarity_strategy: :fact_key_and_text
         }
       })
       |> Map.put(:extraction_context, extraction_context_meta(opts))
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
         {:ok, record} <- build_record(attrs, context.namespace, context.now, scope) do
      context.store_mod.put(record, context.store_opts)
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
    with {:ok, context, scope} <- resolve_mem0_context(target, %{namespace: query.namespace}, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, effective_query} <- attach_namespace(query, context.namespace),
         {:ok, records} <- context.store_mod.query(effective_query, context.store_opts) do
      {:ok, Enum.filter(records, &scope_matches?(&1, scope))}
    end
  end

  def retrieve(target, query_attrs, opts) when is_list(query_attrs),
    do: retrieve(target, Map.new(query_attrs), opts)

  def retrieve(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with {:ok, context, scope} <- resolve_mem0_context(target, query_attrs, opts),
         :ok <- context.store_mod.ensure_ready(context.store_opts),
         {:ok, query} <- build_query(query_attrs, context.namespace),
         {:ok, records} <- context.store_mod.query(query, context.store_opts) do
      {:ok, Enum.filter(records, &scope_matches?(&1, scope))}
    end
  end

  def retrieve(_target, _query, _opts), do: {:error, :invalid_query}

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
         {:ok, extracted} <- extract_candidates(normalized_payload, extraction_config),
         {:ok, summary} <- persist_extracted_candidates(extracted, context, scope, normalized_payload) do
      {:ok, summary}
    end
  end

  def ingest(_target, _payload, _opts), do: {:error, :invalid_ingest_payload}

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

  defp normalize_direct_opts(target, opts) when is_list(opts) do
    plugin_state = plugin_state(target)

    if Keyword.has_key?(opts, :provider) or Keyword.has_key?(opts, :provider_opts) do
      with {:ok, provider_ref} <- ProviderRef.resolve(%{}, opts, plugin_state),
           true <- provider_ref.module == __MODULE__ || {:error, :invalid_provider},
           runtime_opts <- ProviderRef.runtime_opts(provider_ref, opts) do
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

  defp extraction_config(opts) when is_list(opts) do
    provider_opts = normalize_provider_opts(Keyword.get(opts, :provider_opts, []))
    extraction = Keyword.get(provider_opts, :extraction, @default_extraction)
    normalize_extraction_config(extraction)
  end

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

  defp resolve_scope_value(dimension, target, opts, defaults) do
    normalize_scope_value!(
      pick_runtime_scope(opts, dimension) ||
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

  defp build_record(attrs, namespace, now, scope, mem0_metadata \\ %{}) do
    attrs =
      attrs
      |> Map.drop([:provider, "provider"])
      |> Map.put(:namespace, namespace)
      |> Map.put_new(:observed_at, now)
      |> Map.update(:metadata, annotate_mem0_metadata(%{}, scope, mem0_metadata), &annotate_mem0_metadata(&1, scope, mem0_metadata))

    Record.new(attrs, now: now)
  end

  defp build_query(attrs, namespace) do
    attrs =
      attrs
      |> Map.drop([:provider, "provider"])
      |> Map.put_new(:namespace, namespace)

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
          {:ok, candidate} -> %{acc | candidates: acc.candidates ++ [candidate]}
          {:skip, reason} -> %{acc | skipped: acc.skipped ++ [%{reason: reason, content: sentence, origin: entry.origin}]}
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
    with {:ok, pattern, captures} <- parse_candidate_sentence(sentence) do
      {:ok,
       build_candidate(pattern, captures, sentence, entry, summary, extraction_config)}
    else
      :error -> {:skip, :no_candidate}
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

    case pattern do
      :favorite_set ->
        slot = normalize_fact_fragment(Map.fetch!(captures, "slot"))
        value = normalize_fact_fragment(Map.fetch!(captures, "value"))
        build_fact_candidate(base, :upsert, "favorite:#{slot}", value, "favorite #{slot}", sentence)

      :favorite_delete ->
        slot = normalize_fact_fragment(Map.fetch!(captures, "slot"))
        value = normalize_fact_fragment(Map.fetch!(captures, "value"))
        build_fact_candidate(base, :delete, "favorite:#{slot}", value, "favorite #{slot}", sentence)

      :location_set ->
        value = normalize_fact_fragment(Map.fetch!(captures, "value"))
        build_fact_candidate(base, :upsert, "location:home", value, "location home", sentence)

      :location_delete ->
        value = normalize_fact_fragment(Map.fetch!(captures, "value"))
        build_fact_candidate(base, :delete, "location:home", value, "location home", sentence)

      :tool_set ->
        slot = normalize_fact_fragment(Map.fetch!(captures, "slot"))
        value = normalize_fact_fragment(Map.fetch!(captures, "value"))
        build_fact_candidate(base, :upsert, "tool:#{slot}", value, "tool #{slot}", sentence)

      :tool_delete ->
        slot = normalize_fact_fragment(Map.fetch!(captures, "slot"))
        value = normalize_fact_fragment(Map.fetch!(captures, "value"))
        build_fact_candidate(base, :delete, "tool:#{slot}", value, "tool #{slot}", sentence)

      :preference_set ->
        slot = normalize_fact_fragment(Map.fetch!(captures, "slot"))
        value = normalize_fact_fragment(Map.fetch!(captures, "value"))
        build_fact_candidate(base, :upsert, "preference:#{slot}", value, "preference #{slot}", sentence)

      :name_set ->
        value = normalize_fact_fragment(Map.fetch!(captures, "value"))
        build_fact_candidate(base, :upsert, "identity:name", value, "identity name", sentence)

      :project_set ->
        value = normalize_fact_fragment(Map.fetch!(captures, "value"))
        build_fact_candidate(base, :upsert, "work:project", value, "work project", sentence)
    end
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
          {:ok,
           :update,
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
      |> Enum.filter(&scope_matches?(&1, scope))
      |> Enum.filter(&mem0_managed_record?(&1))
      |> Enum.filter(&similar_candidate_record?(&1, candidate))
      |> Enum.sort_by(& &1.observed_at, :desc)
    else
      _ -> []
    end
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

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp value(_map, _key, default), do: default

  defp plugin_state(%{state: %{} = state}),
    do: Map.get(state, Jido.Memory.Runtime.plugin_state_key(), %{}) |> normalize_metadata()

  defp plugin_state(%{} = map),
    do: Map.get(map, Jido.Memory.Runtime.plugin_state_key(), %{}) |> normalize_metadata()

  defp plugin_state(_target), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
