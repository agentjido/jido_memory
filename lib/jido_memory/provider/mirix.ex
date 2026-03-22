defmodule Jido.Memory.Provider.Mirix do
  @moduledoc """
  Built-in MIRIX-inspired provider with typed memory managers and routed retrieval.

  MIRIX keeps the canonical `Jido.Memory.Record` model while routing records across
  dedicated memory-type stores for core, episodic, semantic, procedural,
  resource, and protected vault memory.
  """

  @behaviour Jido.Memory.Provider
  @behaviour Jido.Memory.Capability.ExplainableRetrieval
  @behaviour Jido.Memory.Capability.Ingestion

  alias Jido.Memory.{ProviderRef, Query, Record, Store}

  defmodule Core do
    @moduledoc false
    def memory_type, do: :core
    def canonical_class, do: :working
    def public?, do: true
    def responsibility, do: :persistent_user_and_agent_facts
  end

  defmodule Episodic do
    @moduledoc false
    def memory_type, do: :episodic
    def canonical_class, do: :episodic
    def public?, do: true
    def responsibility, do: :time_stamped_events
  end

  defmodule Semantic do
    @moduledoc false
    def memory_type, do: :semantic
    def canonical_class, do: :semantic
    def public?, do: true
    def responsibility, do: :abstract_facts
  end

  defmodule Procedural do
    @moduledoc false
    def memory_type, do: :procedural
    def canonical_class, do: :procedural
    def public?, do: true
    def responsibility, do: :stepwise_workflows
  end

  defmodule Resource do
    @moduledoc false
    def memory_type, do: :resource
    def canonical_class, do: :working
    def public?, do: true
    def responsibility, do: :resource_artifacts
  end

  defmodule Vault do
    @moduledoc false
    def memory_type, do: :vault
    def canonical_class, do: :working
    def public?, do: false
    def responsibility, do: :protected_exact_preservation
  end

  defmodule MetaRouter do
    @moduledoc false

    def route_write(attrs, context) when is_map(attrs) do
      attrs
      |> explicit_memory_type()
      |> case do
        nil -> derive_memory_type(attrs, context)
        type -> {:ok, type}
      end
    end

    def route_ingestion_entry(entry, context) when is_map(entry) do
      entry
      |> explicit_memory_type()
      |> case do
        nil -> derive_ingestion_type(entry, context)
        type -> {:ok, type}
      end
    end

    def plan_retrieval(%Query{} = query, context) do
      requested = requested_memory_types(query, context)
      planner_mode = planner_mode(query, context)
      resource_scope = extension_value(query, :resource_scope)

      selected =
        requested
        |> apply_resource_scope(resource_scope)
        |> Enum.filter(&(&1 in context.public_memory_types))
        |> Enum.uniq()

      {:ok,
       %{
         requested_memory_types: requested,
         selected_memory_types: selected,
         planner_mode: planner_mode,
         resource_scope: resource_scope,
         passes: [%{name: :primary, memory_types: selected, strategy: :store_query}]
       }}
    end

    defp explicit_memory_type(attrs) do
      case value(attrs, :memory_type) || value(attrs, :mirix_memory_type) do
        nil -> nil
        other -> normalize_memory_type(other)
      end
    end

    defp derive_memory_type(attrs, _context) do
      with {:ok, class} <- Record.normalize_class(value(attrs, :class, :episodic)) do
        {:ok,
         case class do
           :episodic -> :episodic
           :semantic -> :semantic
           :procedural -> :procedural
           :working -> working_memory_type(attrs)
         end}
      end
    end

    defp derive_ingestion_type(entry, _context) do
      modality = value(entry, :modality)
      class = value(entry, :class)

      if class do
        derive_memory_type(%{class: class}, %{})
      else
        {:ok, modality_memory_type(normalize_modality(modality))}
      end
    end

    defp working_memory_type(attrs) do
      tags = value(attrs, :tags, [])
      text = value(attrs, :text, "")
      lowered_text = if is_binary(text), do: String.downcase(text), else: ""
      lowered_tags = Enum.map(List.wrap(tags), &to_string/1) |> Enum.map(&String.downcase/1)

      cond do
        Enum.any?(lowered_tags, &(&1 in ["resource", "document", "file"])) -> :resource
        String.contains?(lowered_text, "resource") -> :resource
        true -> :core
      end
    end

    defp requested_memory_types(%Query{} = query, context) do
      explicit = extension_value(query, :memory_types)
      from_classes = classes_to_memory_types(query.classes)

      cond do
        is_list(explicit) and explicit != [] ->
          Enum.map(explicit, &normalize_memory_type/1)

        from_classes != [] ->
          from_classes

        planner_mode(query, context) == :focused ->
          focused_memory_types(Query.downcased_text_filter(query) || "")

        true ->
          context.public_memory_types
      end
    end

    defp classes_to_memory_types(classes) do
      classes
      |> Enum.flat_map(fn
        :episodic -> [:episodic]
        :semantic -> [:semantic]
        :procedural -> [:procedural]
        :working -> [:core, :resource]
        _ -> []
      end)
      |> Enum.uniq()
    end

    defp planner_mode(%Query{} = query, context) do
      case extension_value(query, :planner_mode) do
        nil -> Keyword.get(context.retrieval, :planner_mode, :broad)
        :focused -> :focused
        "focused" -> :focused
        _ -> :broad
      end
    end

    defp extension_value(%Query{extensions: extensions}, key) do
      case Map.get(extensions, :mirix, Map.get(extensions, "mirix")) do
        %{} = mirix -> Map.get(mirix, key, Map.get(mirix, Atom.to_string(key)))
        _ -> nil
      end
    end

    defp focused_memory_types(text) do
      cond do
        contains_any?(text, ["workflow", "procedure"]) -> [:procedural]
        contains_any?(text, ["resource", "document"]) -> [:resource]
        String.contains?(text, "fact") -> [:semantic]
        true -> [:core, :episodic]
      end
    end

    defp apply_resource_scope(memory_types, scope) do
      case normalize_resource_scope(scope) do
        :only -> [:resource]
        :exclude -> Enum.reject(memory_types, &(&1 == :resource))
        _ -> memory_types
      end
    end

    defp contains_any?(text, needles), do: Enum.any?(needles, &String.contains?(text, &1))

    defp modality_memory_type(modality) when modality in [:image, :file, :document, :audio], do: :resource
    defp modality_memory_type(modality) when modality in [:workflow, :procedure], do: :procedural
    defp modality_memory_type(:fact), do: :semantic
    defp modality_memory_type(_modality), do: :episodic

    defp normalize_resource_scope(scope) when scope in [:only, :exclude], do: scope

    defp normalize_resource_scope(scope) when is_binary(scope) do
      case String.downcase(String.trim(scope)) do
        "only" -> :only
        "exclude" -> :exclude
        _ -> :all
      end
    end

    defp normalize_resource_scope(_scope), do: :all

    defp normalize_memory_type(type) when type in [:core, :episodic, :semantic, :procedural, :resource, :vault],
      do: type

    defp normalize_memory_type(type) when is_binary(type) do
      case String.downcase(String.trim(type)) do
        "core" -> :core
        "episodic" -> :episodic
        "semantic" -> :semantic
        "procedural" -> :procedural
        "resource" -> :resource
        "vault" -> :vault
        _ -> :core
      end
    end

    defp normalize_memory_type(_type), do: :core

    defp normalize_modality(value) when is_atom(value), do: value

    defp normalize_modality(value) when is_binary(value),
      do: String.trim(value) |> String.downcase() |> String.to_atom()

    defp normalize_modality(_value), do: :text

    defp value(map, key, default \\ nil), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  @default_routing [default_working_type: :core]
  @default_retrieval [planner_mode: :broad]
  @default_governance [vault_access: :provider_direct]

  @manager_specs [
    %{type: :core, module: Core, key: :core_store, public?: true},
    %{type: :episodic, module: Episodic, key: :episodic_store, public?: true},
    %{type: :semantic, module: Semantic, key: :semantic_store, public?: true},
    %{type: :procedural, module: Procedural, key: :procedural_store, public?: true},
    %{type: :resource, module: Resource, key: :resource_store, public?: true},
    %{type: :vault, module: Vault, key: :vault_store, public?: false}
  ]

  @default_stores %{
    core_store: {Jido.Memory.Store.ETS, [table: :jido_memory_mirix_core]},
    episodic_store: {Jido.Memory.Store.ETS, [table: :jido_memory_mirix_episodic]},
    semantic_store: {Jido.Memory.Store.ETS, [table: :jido_memory_mirix_semantic]},
    procedural_store: {Jido.Memory.Store.ETS, [table: :jido_memory_mirix_procedural]},
    resource_store: {Jido.Memory.Store.ETS, [table: :jido_memory_mirix_resource]},
    vault_store: {Jido.Memory.Store.ETS, [table: :jido_memory_mirix_vault]}
  }

  @capabilities %{
    core: true,
    retrieval: %{
      explainable: true,
      active: true,
      memory_types: true,
      provider_extensions: true,
      tiers: false
    },
    lifecycle: %{consolidate: false, inspect: false},
    ingestion: %{batch: true, multimodal: true, routed: true, access: :provider_direct},
    operations: %{},
    governance: %{protected_memory: true, exact_preservation: true, access: :provider_direct},
    hooks: %{}
  }

  @type memory_type :: :core | :episodic | :semantic | :procedural | :resource | :vault

  @type context :: %{
          namespace: String.t(),
          now: integer(),
          stores: %{memory_type() => {module(), keyword()}},
          routing: keyword(),
          retrieval: keyword(),
          governance: keyword(),
          public_memory_types: [memory_type()]
        }

  @impl true
  def validate_config(opts) when is_list(opts) do
    with :ok <- validate_namespace(Keyword.get(opts, :namespace)),
         :ok <- validate_store_config(opts),
         :ok <- validate_keyword_block(Keyword.get(opts, :routing, @default_routing), :invalid_routing_opts),
         :ok <- validate_keyword_block(Keyword.get(opts, :retrieval, @default_retrieval), :invalid_retrieval_opts) do
      validate_keyword_block(Keyword.get(opts, :governance, @default_governance), :invalid_governance_opts)
    end
  end

  def validate_config(_opts), do: {:error, :invalid_provider_opts}

  @impl true
  def child_specs(_opts), do: []

  @impl true
  def init(opts) do
    with :ok <- validate_config(opts),
         {:ok, stores} <- normalize_store_map(opts),
         :ok <- ensure_stores_ready(stores) do
      public_types = public_memory_types()

      {:ok,
       %{
         provider: __MODULE__,
         defaults: %{
           namespace: normalize_optional_namespace(Keyword.get(opts, :namespace)),
           stores: stores
         },
         managers: manager_descriptors(),
         routing: Keyword.get(opts, :routing, @default_routing),
         retrieval: Keyword.get(opts, :retrieval, @default_retrieval),
         governance: Keyword.get(opts, :governance, @default_governance),
         public_memory_types: public_types,
         explainability: %{
           payload_version: 1,
           canonical_fields: [:provider, :namespace, :query, :result_count, :results, :extensions],
           result_fields: [:id, :memory_type, :rank, :matched_on, :ranking_context],
           extensions: [:mirix]
         },
         capabilities: @capabilities
       }}
    end
  end

  @impl true
  def capabilities(provider_meta), do: Map.get(provider_meta, :capabilities, @capabilities)

  @impl true
  def remember(target, attrs, opts) when is_list(attrs), do: remember(target, Map.new(attrs), opts)

  def remember(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    with {:ok, context} <- resolve_context(target, attrs, opts),
         {:ok, memory_type} <- MetaRouter.route_write(attrs, context),
         true <- memory_type != :vault || {:error, :protected_memory_requires_direct_access},
         {:ok, record} <- build_record(attrs, context.namespace, memory_type, context.now) do
      persist_record(record, context, memory_type)
    end
  end

  def remember(_target, _attrs, _opts), do: {:error, :invalid_attrs}

  @impl true
  def get(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{}, opts) do
      get_from_memory_types(id, context, select_public_memory_types(opts, context))
    end
  end

  def get(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def retrieve(target, %Query{} = query, opts) when is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{namespace: query.namespace}, opts),
         {:ok, plan} <- MetaRouter.plan_retrieval(query, context),
         {:ok, bundles} <- retrieve_bundles(query, context, plan.selected_memory_types) do
      {:ok, merged_records(bundles, plan.selected_memory_types, query)}
    end
  end

  def retrieve(target, query_attrs, opts) when is_list(query_attrs), do: retrieve(target, Map.new(query_attrs), opts)

  def retrieve(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with {:ok, query} <- build_query(query_attrs),
         {:ok, context} <- resolve_context(target, query_attrs, opts),
         {:ok, plan} <- MetaRouter.plan_retrieval(query, context),
         {:ok, bundles} <- retrieve_bundles(query, context, plan.selected_memory_types) do
      {:ok, merged_records(bundles, plan.selected_memory_types, query)}
    end
  end

  def retrieve(_target, _query, _opts), do: {:error, :invalid_query}

  @impl true
  def explain_retrieval(target, %Query{} = query, opts) when is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{namespace: query.namespace}, opts),
         {:ok, plan} <- MetaRouter.plan_retrieval(query, context),
         {:ok, bundles} <- retrieve_bundles(query, context, plan.selected_memory_types) do
      {:ok, build_explanation(query, context, plan, bundles)}
    end
  end

  def explain_retrieval(target, query_attrs, opts) when is_list(query_attrs),
    do: explain_retrieval(target, Map.new(query_attrs), opts)

  def explain_retrieval(target, query_attrs, opts) when is_map(query_attrs) and is_list(opts) do
    with {:ok, query} <- build_query(query_attrs),
         {:ok, context} <- resolve_context(target, query_attrs, opts),
         {:ok, plan} <- MetaRouter.plan_retrieval(query, context),
         {:ok, bundles} <- retrieve_bundles(query, context, plan.selected_memory_types) do
      {:ok, build_explanation(query, context, plan, bundles)}
    end
  end

  def explain_retrieval(_target, _query, _opts), do: {:error, :invalid_query}

  @impl true
  def forget(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{}, opts) do
      delete_from_memory_types(id, context, select_public_memory_types(opts, context))
    end
  end

  def forget(_target, _id, _opts), do: {:error, :invalid_id}

  @impl true
  def prune(target, opts) when is_list(opts) do
    with {:ok, context} <- resolve_context(target, %{}, opts) do
      {:ok, Enum.reduce(context.stores, 0, &accumulate_pruned_count/2)}
    end
  end

  def prune(_target, _opts), do: {:error, :invalid_provider_opts}

  @impl true
  def info(provider_meta, :all), do: {:ok, provider_meta}

  def info(provider_meta, fields) when is_list(fields), do: {:ok, Map.take(provider_meta, fields)}
  def info(_provider_meta, _fields), do: {:error, :invalid_info_fields}

  @impl true
  def ingest(target, %{} = payload, opts) when is_list(opts) do
    with {:ok, normalized_opts} <- normalize_direct_opts(target, opts),
         {:ok, context} <- resolve_context(target, %{}, normalized_opts),
         {:ok, entries} <- normalize_ingest_entries(payload) do
      {:ok, reduce_ingest_entries(entries, target, context)}
    end
  end

  def ingest(_target, _payload, _opts), do: {:error, :invalid_ingest_payload}

  @spec put_vault_entry(map() | struct(), map() | keyword(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def put_vault_entry(target, attrs, opts \\ [])

  def put_vault_entry(target, attrs, opts) when is_list(attrs), do: put_vault_entry(target, Map.new(attrs), opts)

  def put_vault_entry(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    with {:ok, normalized_opts} <- normalize_direct_opts(target, opts),
         {:ok, context} <- resolve_context(target, attrs, normalized_opts),
         {:ok, record} <- build_record(attrs, context.namespace, :vault, context.now, exact_preservation: true) do
      persist_record(record, context, :vault)
    end
  end

  def put_vault_entry(_target, _attrs, _opts), do: {:error, :invalid_attrs}

  @spec get_vault_entry(map() | struct(), String.t(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  def get_vault_entry(target, id, opts \\ [])

  def get_vault_entry(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, normalized_opts} <- normalize_direct_opts(target, opts),
         {:ok, context} <- resolve_context(target, %{}, normalized_opts) do
      get_from_memory_types(id, context, [:vault])
    end
  end

  def get_vault_entry(_target, _id, _opts), do: {:error, :invalid_id}

  @spec forget_vault_entry(map() | struct(), String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def forget_vault_entry(target, id, opts \\ [])

  def forget_vault_entry(target, id, opts) when is_binary(id) and is_list(opts) do
    with {:ok, normalized_opts} <- normalize_direct_opts(target, opts),
         {:ok, context} <- resolve_context(target, %{}, normalized_opts) do
      delete_from_memory_types(id, context, [:vault])
    end
  end

  def forget_vault_entry(_target, _id, _opts), do: {:error, :invalid_id}

  defp ingest_entry(_target, %{} = entry, context) do
    with {:ok, memory_type} <- MetaRouter.route_ingestion_entry(entry, context),
         true <- memory_type != :vault || {:skip, :vault_requires_direct_access},
         attrs <- ingestion_attrs(entry, memory_type),
         {:ok, record} <-
           build_record(attrs, context.namespace, memory_type, context.now, source: value(entry, :source)) do
      case persist_record(record, context, memory_type) do
        {:ok, persisted} -> {:ok, persisted, memory_type}
        {:error, reason} -> {:error, reason}
      end
    else
      {:skip, _reason} = skip -> skip
      {:error, _reason} = error -> error
    end
  end

  defp ingestion_attrs(entry, memory_type) do
    metadata = normalize_metadata(value(entry, :metadata, %{}))

    %{
      class: canonical_class(memory_type),
      kind: value(entry, :kind, :ingested),
      text: ingest_text(entry),
      content: %{entry: entry},
      observed_at: value(entry, :observed_at),
      source: value(entry, :source),
      metadata: metadata,
      memory_type: memory_type,
      tags: value(entry, :tags, [])
    }
  end

  defp ingest_text(entry) do
    case value(entry, :content) do
      content when is_binary(content) -> content
      %{} = content -> value(content, :text, inspect(content))
      other -> inspect(other)
    end
  end

  defp build_query(%Query{} = query), do: {:ok, query}
  defp build_query(query_attrs) when is_map(query_attrs), do: Query.new(Map.drop(query_attrs, [:provider, "provider"]))

  defp resolve_context(target, attrs, opts) when is_map(attrs) and is_list(opts) do
    provider_opts = normalize_keyword(Keyword.get(opts, :provider_opts, []))
    now = Keyword.get(opts, :now, System.system_time(:millisecond))

    with {:ok, namespace} <- resolve_namespace(target, attrs, opts, provider_opts),
         {:ok, stores} <- normalize_store_map(provider_opts, attrs, opts),
         :ok <- ensure_stores_ready(stores) do
      {:ok,
       %{
         namespace: namespace,
         now: now,
         stores: stores,
         routing: resolve_block(:routing, provider_opts, opts, @default_routing),
         retrieval: resolve_block(:retrieval, provider_opts, opts, @default_retrieval),
         governance: resolve_block(:governance, provider_opts, opts, @default_governance),
         public_memory_types: public_memory_types()
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

  defp normalize_store_map(opts), do: normalize_store_map(opts, %{}, [])

  defp normalize_store_map(provider_opts, attrs, opts) do
    @manager_specs
    |> Enum.reduce_while({:ok, %{}}, fn spec, {:ok, acc} ->
      case normalize_store_for(spec.key, provider_opts, attrs, opts) do
        {:ok, store} -> {:cont, {:ok, Map.put(acc, spec.type, store)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp normalize_store_for(key, provider_opts, attrs, opts) do
    store_value =
      pick_value(opts, attrs, key) ||
        Keyword.get(provider_opts, key) ||
        Map.fetch!(@default_stores, key)

    store_opts =
      pick_value(opts, attrs, store_opts_key(key), []) ||
        Keyword.get(provider_opts, store_opts_key(key), [])

    with {:ok, {store_mod, base_opts}} <- Store.normalize_store(store_value),
         true <- is_list(store_opts) do
      {:ok, {store_mod, Keyword.merge(base_opts, store_opts)}}
    else
      false -> {:error, :invalid_store_opts}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_stores_ready(stores) do
    Enum.reduce_while(stores, :ok, fn {_type, {store_mod, store_opts}}, :ok ->
      case store_mod.ensure_ready(store_opts) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_store_config(opts) do
    Enum.reduce_while(@manager_specs, :ok, fn spec, :ok ->
      validate_store_spec(spec, opts)
    end)
  end

  defp build_record(attrs, namespace, memory_type, now, extra_meta \\ []) do
    metadata =
      attrs
      |> value(:metadata, %{})
      |> normalize_metadata()
      |> annotate_mirix_metadata(memory_type, extra_meta)

    attrs =
      attrs
      |> Map.drop([
        :provider,
        "provider",
        :provider_opts,
        "provider_opts",
        :memory_type,
        "memory_type",
        :mirix_memory_type,
        "mirix_memory_type"
      ])
      |> Map.put(:namespace, namespace)
      |> Map.put(:class, canonical_class(memory_type))
      |> Map.put_new(:observed_at, now)
      |> Map.put(:metadata, metadata)

    Record.new(attrs, now: now)
  end

  defp persist_record(%Record{} = record, context, memory_type) do
    {store_mod, store_opts} = Map.fetch!(context.stores, memory_type)
    store_mod.put(record, store_opts)
  end

  defp get_from_memory_types(id, context, memory_types) do
    Enum.reduce_while(memory_types, {:error, :not_found}, fn memory_type, _acc ->
      {store_mod, store_opts} = Map.fetch!(context.stores, memory_type)

      case Store.fetch(store_mod, {context.namespace, id}, store_opts) do
        {:ok, record} -> {:halt, {:ok, record}}
        {:error, :not_found} -> {:cont, {:error, :not_found}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp delete_from_memory_types(id, context, memory_types) do
    {deleted?, error} =
      Enum.reduce(memory_types, {false, nil}, fn memory_type, {deleted?, error} ->
        merge_delete_result(delete_from_memory_type(id, context, memory_type), deleted?, error)
      end)

    if error, do: {:error, error}, else: {:ok, deleted?}
  end

  defp retrieve_bundles(%Query{} = query, context, memory_types) do
    bundle_query = %{
      query
      | namespace: context.namespace,
        limit: max(query.limit * max(length(memory_types), 1), query.limit)
    }

    bundles =
      Enum.reduce(memory_types, [], fn memory_type, acc ->
        {store_mod, store_opts} = Map.fetch!(context.stores, memory_type)

        case store_mod.query(bundle_query, store_opts) do
          {:ok, records} -> [%{memory_type: memory_type, records: records, pass: :primary} | acc]
          {:error, _reason} -> acc
        end
      end)
      |> Enum.reverse()

    {:ok, bundles}
  end

  defp merged_records(bundles, selected_memory_types, %Query{} = query) do
    bundles
    |> Enum.flat_map(fn bundle ->
      Enum.map(bundle.records, &%{memory_type: bundle.memory_type, pass: bundle.pass, record: &1})
    end)
    |> sort_result_entries(selected_memory_types, query.order)
    |> Enum.uniq_by(& &1.record.id)
    |> Enum.take(query.limit)
    |> Enum.map(& &1.record)
  end

  defp build_explanation(%Query{} = query, context, plan, bundles) do
    result_entries =
      bundles
      |> Enum.flat_map(fn bundle ->
        Enum.map(bundle.records, fn record -> %{memory_type: bundle.memory_type, pass: bundle.pass, record: record} end)
      end)
      |> sort_result_entries(plan.selected_memory_types, query.order)
      |> Enum.uniq_by(& &1.record.id)
      |> Enum.take(query.limit)
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, rank} -> explain_result_entry(entry, rank, query, plan.selected_memory_types) end)

    counts = counts_by_memory_type(bundles)
    participating = Enum.filter(plan.selected_memory_types, &(Map.get(counts, &1, 0) > 0))

    %{
      provider: __MODULE__,
      namespace: context.namespace,
      query: summarize_query(query),
      result_count: length(result_entries),
      results: result_entries,
      extensions: %{
        mirix: %{
          payload_version: 1,
          requested_memory_types: plan.requested_memory_types,
          participating_memory_types: participating,
          retrieval_plan: %{
            planner_mode: plan.planner_mode,
            selected_memory_types: plan.selected_memory_types,
            resource_scope: plan.resource_scope,
            passes: plan.passes
          },
          routing_trace: [
            %{
              step: :select_memory_types,
              planner_mode: plan.planner_mode,
              selected_memory_types: plan.selected_memory_types
            },
            %{
              step: :query_memory_types,
              queried_memory_types: plan.selected_memory_types,
              counts_by_memory_type: counts
            }
          ],
          counts_by_memory_type: counts,
          ranking: %{primary: :selected_memory_type_priority, tie_breaker: :observed_at, order: query.order}
        }
      }
    }
  end

  defp explain_result_entry(entry, rank, %Query{} = query, selected_memory_types) do
    %{
      id: entry.record.id,
      memory_type: entry.memory_type,
      rank: rank,
      matched_on: matched_on(entry.record, query),
      ranking_context: %{
        retrieval_pass: entry.pass,
        selected_priority: memory_type_priority(entry.memory_type, selected_memory_types),
        observed_at: entry.record.observed_at
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

  defp sort_result_entries(entries, selected_memory_types, :asc) do
    Enum.sort_by(entries, &sort_key(&1, selected_memory_types, :asc), :asc)
  end

  defp sort_result_entries(entries, selected_memory_types, _order) do
    Enum.sort_by(entries, &sort_key(&1, selected_memory_types, :desc), :asc)
  end

  defp sort_key(
         %{memory_type: memory_type, record: %Record{id: id, observed_at: observed_at}},
         selected_memory_types,
         :asc
       ) do
    {memory_type_priority(memory_type, selected_memory_types), observed_at, id}
  end

  defp sort_key(
         %{memory_type: memory_type, record: %Record{id: id, observed_at: observed_at}},
         selected_memory_types,
         :desc
       ) do
    {memory_type_priority(memory_type, selected_memory_types), -observed_at, id}
  end

  defp memory_type_priority(memory_type, selected_memory_types) do
    Enum.find_index(selected_memory_types, &(&1 == memory_type)) || length(selected_memory_types)
  end

  defp matched_on(%Record{} = record, %Query{} = query) do
    matches = []
    matches = if query.text_contains && is_binary(record.text), do: [:text_contains | matches], else: matches
    matches = if query.classes != [], do: [:class | matches], else: matches
    matches = if query.kinds != [], do: [:kind | matches], else: matches
    Enum.reverse(matches)
  end

  defp counts_by_memory_type(bundles) do
    public_memory_types()
    |> Enum.reduce(%{}, fn type, acc ->
      count =
        bundles
        |> Enum.filter(&(&1.memory_type == type))
        |> Enum.reduce(0, fn bundle, total -> total + length(bundle.records) end)

      Map.put(acc, type, count)
    end)
  end

  defp canonical_class(:core), do: :working
  defp canonical_class(:episodic), do: :episodic
  defp canonical_class(:semantic), do: :semantic
  defp canonical_class(:procedural), do: :procedural
  defp canonical_class(:resource), do: :working
  defp canonical_class(:vault), do: :working

  defp manager_descriptors do
    Enum.map(@manager_specs, fn spec ->
      %{
        memory_type: spec.type,
        module: spec.module,
        public?: spec.public?,
        canonical_class: spec.module.canonical_class(),
        responsibility: spec.module.responsibility()
      }
    end)
  end

  defp public_memory_types do
    @manager_specs
    |> Enum.filter(& &1.public?)
    |> Enum.map(& &1.type)
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

  defp resolve_block(key, provider_opts, opts, default) do
    case Keyword.fetch(opts, key) do
      {:ok, block} when is_list(block) -> block
      _ -> Keyword.get(provider_opts, key, default)
    end
  end

  defp annotate_mirix_metadata(metadata, memory_type, extra_meta) do
    extra_meta =
      Enum.into(extra_meta, %{}, fn {key, value} ->
        {metadata_key(key), value}
      end)

    mirix =
      metadata
      |> Map.get("mirix", %{})
      |> normalize_metadata()
      |> stringify_metadata_keys()
      |> Map.merge(extra_meta)
      |> Map.put("memory_type", Atom.to_string(memory_type))
      |> Map.put_new("source_provider", "mirix")

    Map.put(metadata, "mirix", mirix)
  end

  defp normalize_metadata(%{} = metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}

  defp accumulate_pruned_count({_type, {store_mod, store_opts}}, acc) do
    case store_mod.prune_expired(store_opts) do
      {:ok, pruned} -> acc + pruned
      _ -> acc
    end
  end

  defp normalize_ingest_entries(%{} = payload) do
    case value(payload, :entries, []) do
      entries when is_list(entries) and entries != [] -> {:ok, entries}
      _ -> {:error, :invalid_ingest_payload}
    end
  end

  defp reduce_ingest_entries(entries, target, context) do
    result =
      Enum.reduce(entries, %{counts: %{}, record_ids: [], skipped: []}, fn entry, acc ->
        reduce_ingest_entry(acc, ingest_entry(target, entry, context))
      end)

    %{
      provider: __MODULE__,
      counts_by_memory_type: result.counts,
      record_ids: Enum.reverse(result.record_ids),
      skipped: Enum.reverse(result.skipped)
    }
  end

  defp reduce_ingest_entry(acc, {:ok, record, memory_type}) do
    %{
      acc
      | counts: Map.update(acc.counts, memory_type, 1, &(&1 + 1)),
        record_ids: [record.id | acc.record_ids]
    }
  end

  defp reduce_ingest_entry(acc, {:skip, reason}), do: %{acc | skipped: [reason | acc.skipped]}
  defp reduce_ingest_entry(acc, {:error, reason}), do: %{acc | skipped: [reason | acc.skipped]}

  defp validate_store_spec(spec, opts) do
    value = Keyword.get(opts, spec.key)
    store_opts = Keyword.get(opts, store_opts_key(spec.key), [])

    cond do
      is_nil(value) and is_list(store_opts) ->
        {:cont, :ok}

      is_nil(value) ->
        {:halt, {:error, :invalid_store_opts}}

      not is_list(store_opts) ->
        {:halt, {:error, :invalid_store_opts}}

      true ->
        case Store.normalize_store(value) do
          {:ok, _} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end
  end

  defp delete_from_memory_type(id, context, memory_type) do
    {store_mod, store_opts} = Map.fetch!(context.stores, memory_type)

    case store_mod.get({context.namespace, id}, store_opts) do
      {:ok, _record} -> delete_existing_record(store_mod, context.namespace, id, store_opts)
      :not_found -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_existing_record(store_mod, namespace, id, store_opts) do
    case store_mod.delete({namespace, id}, store_opts) do
      :ok -> {:ok, true}
      {:error, reason} -> {:error, reason}
    end
  end

  defp merge_delete_result({:ok, did_delete?}, deleted?, error), do: {deleted? or did_delete?, error}
  defp merge_delete_result({:error, reason}, deleted?, _error), do: {deleted?, reason}

  defp stringify_metadata_keys(metadata) do
    Enum.into(metadata, %{}, fn {key, value} -> {metadata_key(key), value} end)
  end

  defp metadata_key(key) when is_atom(key), do: Atom.to_string(key)
  defp metadata_key(key) when is_binary(key), do: key
  defp metadata_key(key), do: to_string(key)

  defp validate_keyword_block(block, _reason) when is_list(block), do: :ok
  defp validate_keyword_block(_block, reason), do: {:error, reason}

  defp validate_namespace(nil), do: :ok
  defp validate_namespace(value) when is_binary(value) or is_atom(value), do: :ok
  defp validate_namespace(_value), do: {:error, :invalid_namespace}

  defp store_opts_key(key), do: String.to_atom("#{key}_opts")

  defp normalize_optional_namespace(nil), do: nil
  defp normalize_optional_namespace(namespace) when is_binary(namespace), do: String.trim(namespace)
  defp normalize_optional_namespace(namespace) when is_atom(namespace), do: Atom.to_string(namespace)
  defp normalize_optional_namespace(_namespace), do: nil

  defp normalize_keyword(opts) when is_list(opts), do: opts
  defp normalize_keyword(_opts), do: []

  defp select_public_memory_types(opts, context) do
    explicit = Keyword.get(opts, :memory_types) || Keyword.get(opts, :memory_type)

    case explicit do
      nil ->
        context.public_memory_types

      value ->
        List.wrap(value) |> Enum.map(&normalize_memory_type/1) |> Enum.filter(&(&1 in context.public_memory_types))
    end
  end

  defp normalize_memory_type(type) when type in [:core, :episodic, :semantic, :procedural, :resource, :vault], do: type

  defp normalize_memory_type(type) when is_binary(type) do
    case String.downcase(String.trim(type)) do
      "core" -> :core
      "episodic" -> :episodic
      "semantic" -> :semantic
      "procedural" -> :procedural
      "resource" -> :resource
      "vault" -> :vault
      _ -> :core
    end
  end

  defp normalize_memory_type(_type), do: :core

  defp target_id(%{id: id}) when is_binary(id), do: id
  defp target_id(%{agent: %{id: id}}) when is_binary(id), do: id
  defp target_id(_), do: nil

  defp plugin_state(%{state: %{} = state}),
    do: Map.get(state, Jido.Memory.Runtime.plugin_state_key(), %{}) |> normalize_metadata()

  defp plugin_state(%{} = map), do: Map.get(map, Jido.Memory.Runtime.plugin_state_key(), %{}) |> normalize_metadata()
  defp plugin_state(_), do: %{}

  defp pick_value(opts, attrs, key, default \\ nil) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
    end
  end

  defp value(map, key, default \\ nil), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false
end
