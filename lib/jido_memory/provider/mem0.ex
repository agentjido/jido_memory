defmodule Jido.Memory.Provider.Mem0 do
  @moduledoc """
  Built-in Mem0-style provider baseline.

  The first cut keeps the canonical `Jido.Memory.Provider` surface and uses the
  existing store-backed core flow while reserving metadata and capabilities for
  later extraction, reconciliation, scoped identity, and graph augmentation
  work.
  """

  @behaviour Jido.Memory.Provider

  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.{Query, Record, Store}

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
    ingestion: %{batch: false, multimodal: false, routed: false, access: :provider_direct},
    operations: %{feedback: :provider_direct, export: :provider_direct, history: :provider_direct},
    governance: %{protected_memory: false, exact_preservation: false, access: :none},
    hooks: %{}
  }

  @impl true
  def validate_config(opts) when is_list(opts) do
    with :ok <- Basic.validate_config(opts) do
      validate_scoped_identity(Keyword.get(opts, :scoped_identity, []))
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
         maintenance: %{reconciliation: :provider_direct, feedback: :provider_direct, history: :provider_direct}
       })
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
         {:ok, scope} <- resolve_scope(target, opts) do
      {:ok, context, scope}
    end
  end

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

  defp validate_scoped_identity(scoped_identity) do
    case normalize_scoped_identity(scoped_identity) do
      {:ok, _normalized} -> :ok
      {:error, _reason} = error -> error
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

  defp build_record(attrs, namespace, now, scope) do
    attrs =
      attrs
      |> Map.drop([:provider, "provider"])
      |> Map.put(:namespace, namespace)
      |> Map.put_new(:observed_at, now)
      |> Map.update(:metadata, annotate_mem0_metadata(%{}, scope), &annotate_mem0_metadata(&1, scope))

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

  defp annotate_mem0_metadata(metadata, scope) do
    mem0 =
      metadata
      |> Map.get("mem0", %{})
      |> normalize_metadata()
      |> stringify_map_keys()
      |> Map.put("scope", scope_to_metadata(scope))
      |> Map.put_new("source_provider", "mem0")

    Map.put(metadata, "mem0", mem0)
  end

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
end
