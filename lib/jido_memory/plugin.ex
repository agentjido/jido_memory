require Jido.Memory.Actions.Forget
require Jido.Memory.Actions.Recall
require Jido.Memory.Actions.Remember
require Jido.Memory.Actions.Retrieve

defmodule Jido.Memory.PluginSupport do
  @moduledoc false

  alias Jido.Memory.Actions.{Forget, Recall, Remember, Retrieve}
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.ProviderRef
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store
  alias Jido.Signal

  @default_store {Jido.Memory.Store.ETS, [table: :jido_memory]}

  @default_capture_patterns [
    "ai.react.query",
    "ai.llm.response",
    "ai.tool.result"
  ]

  @type mode :: :provider_aware | :legacy_ets

  @spec state_schema() :: Zoi.schema()
  def state_schema do
    Zoi.object(%{
      provider: Zoi.any() |> Zoi.optional(),
      namespace: Zoi.string() |> Zoi.optional(),
      store: Zoi.any() |> Zoi.optional(),
      auto_capture: Zoi.boolean() |> Zoi.default(true),
      capture_signal_patterns:
        Zoi.list(Zoi.string())
        |> Zoi.default(@default_capture_patterns),
      capture_rules: Zoi.map() |> Zoi.default(%{})
    })
  end

  @spec config_schema() :: Zoi.schema()
  def config_schema do
    Zoi.object(%{
      provider: Zoi.any() |> Zoi.optional(),
      provider_opts: Zoi.any() |> Zoi.default([]),
      store: Zoi.any() |> Zoi.default(@default_store),
      store_opts: Zoi.list(Zoi.any()) |> Zoi.default([]),
      namespace: Zoi.string() |> Zoi.optional(),
      namespace_mode: Zoi.atom() |> Zoi.default(:per_agent),
      shared_namespace: Zoi.string() |> Zoi.optional(),
      auto_capture: Zoi.boolean() |> Zoi.default(true),
      capture_signal_patterns:
        Zoi.list(Zoi.string())
        |> Zoi.default(@default_capture_patterns),
      capture_rules: Zoi.map() |> Zoi.default(%{})
    })
  end

  @spec actions() :: [module()]
  def actions, do: [Remember, Retrieve, Recall, Forget]

  @spec signal_routes() :: [{String.t(), module()}]
  def signal_routes do
    [
      {"remember", Remember},
      {"retrieve", Retrieve},
      {"recall", Recall},
      {"forget", Forget}
    ]
  end

  @spec mount(map(), map() | keyword(), mode()) :: {:ok, map()} | {:error, term()}
  def mount(agent, config, mode) do
    config_map = normalize_map(config)

    with {:ok, provider_ref} <- resolve_provider_ref(config_map, mode),
         {:ok, legacy_state} <- resolve_legacy_state(agent, config_map, provider_ref, mode) do
      provider_ref = maybe_enrich_provider_ref(provider_ref, legacy_state)

      {:ok,
       legacy_state
       |> Map.put(:provider, provider_ref)
       |> Map.put(:auto_capture, map_get(config_map, :auto_capture, true))
       |> Map.put(:capture_signal_patterns, map_get(config_map, :capture_signal_patterns, @default_capture_patterns))
       |> Map.put(:capture_rules, map_get(config_map, :capture_rules, %{}))}
    end
  end

  @spec handle_signal(Signal.t(), map()) :: {:ok, :continue}
  def handle_signal(%Signal{} = signal, context) do
    plugin_state =
      context
      |> map_get(:agent, %{})
      |> map_get(:state, %{})
      |> map_get(Runtime.plugin_state_key(), %{})

    auto_capture = map_get(plugin_state, :auto_capture, true)
    patterns = map_get(plugin_state, :capture_signal_patterns, @default_capture_patterns)

    should_capture? = auto_capture and signal_matches_any?(signal.type, patterns)

    if should_capture? do
      case build_capture_attrs(signal, plugin_state) do
        :skip ->
          :ok

        attrs when is_map(attrs) ->
          _ = Runtime.remember(map_get(context, :agent, %{}), attrs, [])
          :ok
      end
    else
      :ok
    end

    {:ok, :continue}
  rescue
    _ -> {:ok, :continue}
  end

  @spec on_checkpoint(term(), map()) :: :keep
  def on_checkpoint(_plugin_state, _context), do: :keep

  @spec on_restore(term(), map(), mode()) :: {:ok, map() | nil}
  def on_restore(pointer, _context, :provider_aware) when is_map(pointer),
    do: {:ok, normalize_state(pointer, :provider_aware)}

  def on_restore(pointer, _context, :legacy_ets) when is_map(pointer), do: {:ok, pointer}
  def on_restore(_pointer, _context, _mode), do: {:ok, nil}

  defp resolve_provider_ref(config_map, :legacy_ets) do
    provider_ref = {Basic, legacy_provider_opts(config_map)}

    with {:ok, provider_ref} <- ProviderRef.normalize(provider_ref),
         {:ok, _provider_meta} <- provider_ref.module.init(provider_ref.opts) do
      {:ok, provider_ref}
    end
  end

  defp resolve_provider_ref(config_map, :provider_aware) do
    provider_input = map_get(config_map, :provider)
    provider_opts = map_get(config_map, :provider_opts, [])

    if is_nil(provider_input) or is_list(provider_opts) do
      provider_ref = provider_ref_input(provider_input, provider_opts, config_map)

      with {:ok, provider_ref} <- ProviderRef.normalize(provider_ref),
           {:ok, _provider_meta} <- provider_ref.module.init(provider_ref.opts) do
        {:ok, provider_ref}
      end
    else
      {:error, :invalid_provider_opts}
    end
  end

  defp resolve_legacy_state(agent, config_map, %ProviderRef{module: Basic, opts: provider_opts}, _mode) do
    basic_config =
      config_map
      |> put_missing(:namespace, Keyword.get(provider_opts, :namespace))
      |> put_missing(:store, Keyword.get(provider_opts, :store))
      |> put_missing(:store_opts, Keyword.get(provider_opts, :store_opts, []))

    with {:ok, namespace} <- resolve_namespace(agent, basic_config),
         {:ok, {store_mod, store_opts}} <- resolve_store(basic_config),
         :ok <- store_mod.ensure_ready(store_opts) do
      {:ok, %{namespace: namespace, store: {store_mod, store_opts}}}
    end
  end

  defp resolve_legacy_state(_agent, _config_map, _provider_ref, _mode), do: {:ok, %{}}

  defp normalize_state(state, mode) do
    state_map = normalize_map(state)

    provider =
      case map_get(state_map, :provider) do
        nil ->
          resolve_provider_ref(state_map, mode)
          |> case do
            {:ok, provider_ref} -> provider_ref
            _ -> ProviderRef.default()
          end

        provider ->
          case ProviderRef.normalize(provider) do
            {:ok, provider_ref} -> provider_ref
            _ -> ProviderRef.default()
          end
      end

    %{
      provider: provider,
      namespace: normalize_optional_string(map_get(state_map, :namespace)),
      store: map_get(state_map, :store),
      auto_capture: map_get(state_map, :auto_capture, true),
      capture_signal_patterns: map_get(state_map, :capture_signal_patterns, @default_capture_patterns),
      capture_rules: map_get(state_map, :capture_rules, %{})
    }
  end

  defp legacy_provider_opts(config_map) do
    []
    |> maybe_put(:namespace, map_get(config_map, :namespace))
    |> maybe_put(:store, map_get(config_map, :store))
    |> maybe_put(:store_opts, map_get(config_map, :store_opts, []))
  end

  defp resolve_store(config) do
    store_value = map_get(config, :store, @default_store)
    override_opts = map_get(config, :store_opts, [])

    with {:ok, {store_mod, base_opts}} <- Store.normalize_store(store_value),
         true <- is_list(override_opts) do
      {:ok, {store_mod, Keyword.merge(base_opts, override_opts)}}
    else
      false -> {:error, :invalid_store_opts}
      {:error, _} = error -> error
    end
  end

  defp resolve_namespace(agent, config) do
    explicit = map_get(config, :namespace)

    case trim_present(explicit) do
      {:ok, namespace} ->
        {:ok, namespace}

      :error ->
        resolve_namespace_from_mode(agent, map_get(config, :namespace_mode, :per_agent), config)
    end
  end

  defp build_capture_attrs(%Signal{} = signal, plugin_state) do
    base =
      case signal.type do
        "ai.react.query" ->
          data = normalize_data(signal.data)

          %{
            class: :episodic,
            kind: :user_query,
            text: pick(data, :query) || pick(data, :text),
            content: data,
            tags: ["ai", "query", signal.type],
            source: signal.source,
            observed_at: signal_timestamp(signal),
            metadata: base_metadata(signal)
          }

        "ai.llm.response" ->
          data = normalize_data(signal.data)

          %{
            class: :episodic,
            kind: :assistant_response,
            text: extract_llm_text(data),
            content: data,
            tags: ["ai", "llm", signal.type],
            source: signal.source,
            observed_at: signal_timestamp(signal),
            metadata: base_metadata(signal)
          }

        "ai.tool.result" ->
          data = normalize_data(signal.data)
          tool_name = pick(data, :tool_name) || pick(data, :name) || "tool"

          %{
            class: :episodic,
            kind: :tool_result,
            text: "#{tool_name} result",
            content: data,
            tags: ["ai", "tool", tool_name, signal.type],
            source: signal.source,
            observed_at: signal_timestamp(signal),
            metadata: base_metadata(signal)
          }

        _ ->
          %{
            class: :working,
            kind: :signal_event,
            text: signal.type,
            content: normalize_data(signal.data),
            tags: ["signal", signal.type],
            source: signal.source,
            observed_at: signal_timestamp(signal),
            metadata: base_metadata(signal)
          }
      end

    rules = map_get(plugin_state, :capture_rules, %{})
    maybe_apply_capture_rule(base, signal.type, rules)
  end

  defp maybe_apply_capture_rule(base, signal_type, rules) when is_map(rules) do
    rule = Map.get(rules, signal_type) || Map.get(rules, safe_existing_atom(signal_type))

    case rule do
      %{skip: true} ->
        :skip

      %{} ->
        merged =
          base
          |> maybe_override(rule, :class)
          |> maybe_override(rule, :kind)
          |> maybe_override(rule, :text)
          |> maybe_override(rule, :source)
          |> merge_tags(rule)

        Map.update(merged, :metadata, %{}, fn metadata ->
          Map.merge(metadata, map_get(rule, :metadata, %{}))
        end)

      _ ->
        base
    end
  end

  defp maybe_apply_capture_rule(base, _signal_type, _rules), do: base

  defp maybe_override(base, rule, key) do
    value = map_get(rule, key)
    if is_nil(value), do: base, else: Map.put(base, key, value)
  end

  defp merge_tags(base, rule) do
    case map_get(rule, :tags) do
      tags when is_list(tags) ->
        tags = Enum.map(tags, &to_string/1)
        Map.put(base, :tags, Enum.uniq(base.tags ++ tags))

      _ ->
        base
    end
  end

  defp extract_llm_text(data) do
    pick(data, :text) ||
      pick(data, :answer) ||
      pick(data, :content) ||
      case pick(data, :result) do
        nil -> nil
        result when is_binary(result) -> result
        result -> inspect(result)
      end
  end

  defp signal_timestamp(%Signal{time: nil}), do: System.system_time(:millisecond)

  defp signal_timestamp(%Signal{time: time}) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _offset} -> DateTime.to_unix(dt, :millisecond)
      _ -> System.system_time(:millisecond)
    end
  end

  defp signal_timestamp(_), do: System.system_time(:millisecond)

  defp base_metadata(%Signal{} = signal) do
    %{
      signal_id: signal.id,
      signal_type: signal.type,
      subject: signal.subject
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_data(%{} = data), do: data
  defp normalize_data(nil), do: %{}
  defp normalize_data(data), do: %{value: data}

  defp signal_matches_any?(_type, []), do: false

  defp signal_matches_any?(type, patterns) when is_binary(type) and is_list(patterns) do
    Enum.any?(patterns, &signal_type_matches?(type, &1))
  end

  defp signal_type_matches?(type, pattern) when type == pattern, do: true

  defp signal_type_matches?(type, pattern) do
    cond do
      String.ends_with?(pattern, ".*") ->
        prefix = String.trim_trailing(pattern, ".*")
        String.starts_with?(type, prefix <> ".")

      String.contains?(pattern, "*") ->
        regex =
          pattern
          |> Regex.escape()
          |> String.replace("\\*", "[^.]*")

        Regex.match?(~r/^#{regex}$/, type)

      true ->
        false
    end
  end

  defp pick(map, key), do: map_get(map, key)

  defp map_get(map, key, default \\ nil)

  defp map_get(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_get(_map, _key, default), do: default

  defp normalize_map(%{} = map), do: map
  defp normalize_map(list) when is_list(list), do: Map.new(list)
  defp normalize_map(_other), do: %{}

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_value), do: nil

  defp provider_ref_input(nil, _provider_opts, config_map), do: {Basic, legacy_provider_opts(config_map)}

  defp provider_ref_input(provider_input, _provider_opts, _config_map)
       when is_tuple(provider_input),
       do: provider_input

  defp provider_ref_input(provider_input, provider_opts, _config_map) when is_atom(provider_input),
    do: {provider_input, provider_opts}

  defp provider_ref_input(provider_input, _provider_opts, _config_map), do: provider_input

  defp resolve_namespace_from_mode(_agent, :shared, config) do
    shared_namespace =
      case trim_present(map_get(config, :shared_namespace)) do
        {:ok, namespace} -> namespace
        :error -> "default"
      end

    {:ok, "shared:" <> shared_namespace}
  end

  defp resolve_namespace_from_mode(agent, _mode, _config) do
    case map_get(agent, :id) do
      id when is_binary(id) and id != "" -> {:ok, "agent:" <> id}
      _ -> {:error, :namespace_required}
    end
  end

  defp trim_present(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      :error
    else
      {:ok, trimmed}
    end
  end

  defp trim_present(_value), do: :error

  defp maybe_enrich_provider_ref(%ProviderRef{module: Basic} = provider_ref, legacy_state) do
    %{provider_ref | opts: enrich_basic_opts(provider_ref.opts, legacy_state)}
  end

  defp maybe_enrich_provider_ref(provider_ref, _legacy_state), do: provider_ref

  defp enrich_basic_opts(provider_opts, legacy_state) do
    provider_opts
    |> maybe_put(:namespace, map_get(legacy_state, :namespace))
    |> maybe_put(:store, map_get(legacy_state, :store))
  end

  defp put_missing(map, _key, nil), do: map

  defp put_missing(map, key, value) when is_atom(key) do
    Map.put_new(map, key, value)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp safe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp safe_existing_atom(_), do: nil
end

previous_ignore_module_conflict = Code.get_compiler_option(:ignore_module_conflict)
Code.put_compiler_option(:ignore_module_conflict, true)

defmodule Jido.Memory.Plugin do
  @moduledoc """
  Provider-aware memory plugin for Jido agents.
  """

  alias Jido.Memory.PluginSupport

  use Jido.Plugin,
    name: "memory",
    state_key: :__memory__,
    actions: PluginSupport.actions(),
    schema: PluginSupport.state_schema(),
    config_schema: PluginSupport.config_schema(),
    singleton: true,
    description: "Provider-aware memory plugin with structured retrieval and auto-capture.",
    capabilities: [:memory]

  @impl Jido.Plugin
  def mount(agent, config), do: PluginSupport.mount(agent, config, :provider_aware)

  @impl Jido.Plugin
  def signal_routes(_config), do: PluginSupport.signal_routes()

  @impl Jido.Plugin
  def handle_signal(signal, context), do: PluginSupport.handle_signal(signal, context)

  @impl Jido.Plugin
  def on_checkpoint(plugin_state, context), do: PluginSupport.on_checkpoint(plugin_state, context)

  @impl Jido.Plugin
  def on_restore(pointer, context), do: PluginSupport.on_restore(pointer, context, :provider_aware)
end

Code.put_compiler_option(:ignore_module_conflict, previous_ignore_module_conflict)

defmodule Jido.Memory.ETSPlugin do
  @moduledoc """
  ETS-backed compatibility wrapper over `Jido.Memory.Plugin`.
  """

  alias Jido.Memory.PluginSupport

  use Jido.Plugin,
    name: "memory",
    state_key: :__memory__,
    actions: PluginSupport.actions(),
    schema: PluginSupport.state_schema(),
    config_schema: PluginSupport.config_schema(),
    singleton: true,
    description: "ETS-backed memory plugin with structured retrieval and auto-capture.",
    capabilities: [:memory]

  @impl Jido.Plugin
  def mount(agent, config), do: PluginSupport.mount(agent, config, :legacy_ets)

  @impl Jido.Plugin
  def signal_routes(_config), do: PluginSupport.signal_routes()

  @impl Jido.Plugin
  def handle_signal(signal, context), do: PluginSupport.handle_signal(signal, context)

  @impl Jido.Plugin
  def on_checkpoint(plugin_state, context), do: PluginSupport.on_checkpoint(plugin_state, context)

  @impl Jido.Plugin
  def on_restore(pointer, context), do: PluginSupport.on_restore(pointer, context, :legacy_ets)
end
