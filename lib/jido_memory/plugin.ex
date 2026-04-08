require Jido.Memory.Actions.Forget
require Jido.Memory.Actions.Recall
require Jido.Memory.Actions.Remember
require Jido.Memory.Actions.Retrieve

defmodule Jido.Memory.ETSPlugin do
  @moduledoc """
  ETS-backed memory plugin for Jido agents.

  This plugin owns `:__memory__` state and keeps only lightweight runtime
  metadata in agent state while records live in ETS.
  """

  alias Jido.Signal
  alias Jido.Memory.Actions.{Forget, Recall, Remember, Retrieve}
  alias Jido.Memory.Helpers
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.ProviderRef
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store

  @default_store {Jido.Memory.Store.ETS, [table: :jido_memory]}

  @default_capture_patterns [
    "ai.react.query",
    "ai.llm.response",
    "ai.tool.result"
  ]

  @state_schema Zoi.object(%{
                  namespace: Zoi.string() |> Zoi.optional(),
                  store: Zoi.any() |> Zoi.default(@default_store),
                  provider: Zoi.any() |> Zoi.optional(),
                  provider_opts: Zoi.list(Zoi.any()) |> Zoi.default([]),
                  auto_capture: Zoi.boolean() |> Zoi.default(true),
                  capture_signal_patterns:
                    Zoi.list(Zoi.string())
                    |> Zoi.default(@default_capture_patterns),
                  capture_rules: Zoi.map() |> Zoi.default(%{})
                })

  @config_schema Zoi.object(%{
                   store: Zoi.any() |> Zoi.default(@default_store),
                   store_opts: Zoi.list(Zoi.any()) |> Zoi.default([]),
                   provider: Zoi.any() |> Zoi.optional(),
                   provider_opts: Zoi.list(Zoi.any()) |> Zoi.default([]),
                   namespace: Zoi.string() |> Zoi.optional(),
                   namespace_mode: Zoi.atom() |> Zoi.default(:per_agent),
                   shared_namespace: Zoi.string() |> Zoi.optional(),
                   auto_capture: Zoi.boolean() |> Zoi.default(true),
                   capture_signal_patterns:
                     Zoi.list(Zoi.string())
                     |> Zoi.default(@default_capture_patterns),
                   capture_rules: Zoi.map() |> Zoi.default(%{})
                 })

  use Jido.Plugin,
    name: "memory",
    state_key: :__memory__,
    actions: [Remember, Retrieve, Recall, Forget],
    schema: @state_schema,
    config_schema: @config_schema,
    singleton: true,
    description: "ETS-backed memory plugin with structured retrieval and auto-capture.",
    capabilities: [:memory]

  @impl Jido.Plugin
  def mount(agent, config) do
    config_map = Helpers.normalize_map(config)

    with {:ok, namespace} <- resolve_namespace(agent, config_map),
         {:ok, {store_mod, store_opts}} <- resolve_store(config_map),
         :ok <- store_mod.ensure_ready(store_opts) do
      store = {store_mod, store_opts}
      provider_ref = build_provider_ref(config_map, namespace, store)

      {:ok, build_plugin_state(config_map, namespace, store, provider_ref)}
    end
  end

  @impl Jido.Plugin
  def signal_routes(_config) do
    [
      {"remember", Remember},
      {"retrieve", Retrieve},
      {"recall", Recall},
      {"forget", Forget}
    ]
  end

  @impl Jido.Plugin
  def handle_signal(%Signal{} = signal, context) do
    agent = Helpers.map_get(context, :agent, %{})
    plugin_state = Helpers.plugin_state(agent, Runtime.plugin_state_key())

    _ = maybe_capture_signal(signal, agent, plugin_state)

    {:ok, :continue}
  rescue
    _ -> {:ok, :continue}
  end

  @impl Jido.Plugin
  def on_checkpoint(_plugin_state, _context), do: :keep

  @impl Jido.Plugin
  def on_restore(pointer, _context) when is_map(pointer), do: {:ok, normalize_state(pointer)}
  def on_restore(_pointer, _context), do: {:ok, nil}

  defp build_provider_ref(config, namespace, store) do
    provider_input = Helpers.map_get(config, :provider)
    provider_opts = normalize_provider_opts(Helpers.map_get(config, :provider_opts, []))

    provider_input
    |> normalize_provider_input(provider_opts)
    |> ProviderRef.normalize()
    |> case do
      {:ok, provider_ref} -> maybe_enrich_basic_provider_ref(provider_ref, namespace, store)
      {:error, _reason} -> ProviderRef.normalize({Basic, [namespace: namespace, store: store]}) |> elem(1)
    end
  end

  defp normalize_state(state) do
    state_map = Helpers.normalize_map(state)
    namespace = Helpers.map_get(state_map, :namespace)
    store = Helpers.map_get(state_map, :store)
    provider_ref = build_provider_ref(state_map, namespace, store)

    build_plugin_state(state_map, namespace, store, provider_ref)
  end

  defp build_plugin_state(source, namespace, store, provider_ref) do
    %{
      namespace: Helpers.normalize_optional_string(namespace),
      store: store,
      provider: provider_ref,
      provider_opts: provider_ref.opts,
      auto_capture: Helpers.map_get(source, :auto_capture, true),
      capture_signal_patterns: Helpers.map_get(source, :capture_signal_patterns, @default_capture_patterns),
      capture_rules: Helpers.map_get(source, :capture_rules, %{})
    }
  end

  @spec resolve_store(map()) :: {:ok, {module(), keyword()}} | {:error, term()}
  defp resolve_store(config) do
    store_value = Helpers.map_get(config, :store, @default_store)
    override_opts = Helpers.map_get(config, :store_opts, [])

    with {:ok, {store_mod, base_opts}} <- Store.normalize_store(store_value),
         true <- is_list(override_opts) do
      {:ok, {store_mod, Keyword.merge(base_opts, override_opts)}}
    else
      false -> {:error, :invalid_store_opts}
      {:error, _} = error -> error
    end
  end

  @spec resolve_namespace(map(), map()) :: {:ok, String.t()} | {:error, term()}
  defp resolve_namespace(agent, config) do
    explicit = Helpers.normalize_optional_string(Helpers.map_get(config, :namespace))

    if is_binary(explicit) do
      {:ok, explicit}
    else
      resolve_namespace_by_mode(agent, config, Helpers.map_get(config, :namespace_mode, :per_agent))
    end
  end

  @spec build_capture_attrs(Signal.t(), map()) :: map() | :skip
  defp build_capture_attrs(%Signal{} = signal, plugin_state) do
    signal
    |> capture_attrs_for_signal()
    |> maybe_apply_capture_rule(signal.type, Helpers.map_get(plugin_state, :capture_rules, %{}))
  end

  defp maybe_capture_signal(signal, agent, plugin_state) do
    if capture_signal?(signal.type, plugin_state) do
      case build_capture_attrs(signal, plugin_state) do
        :skip -> :ok
        attrs when is_map(attrs) -> Runtime.remember(agent, attrs, [])
      end
    else
      :ok
    end
  end

  defp capture_signal?(type, plugin_state) when is_binary(type) do
    Helpers.map_get(plugin_state, :auto_capture, true) and
      signal_matches_any?(type, Helpers.map_get(plugin_state, :capture_signal_patterns, @default_capture_patterns))
  end

  defp capture_attrs_for_signal(%Signal{type: "ai.react.query"} = signal) do
    data = normalize_data(signal.data)

    capture_attrs(signal,
      class: :episodic,
      kind: :user_query,
      text: pick(data, :query) || pick(data, :text),
      content: data,
      tags: ["ai", "query", signal.type]
    )
  end

  defp capture_attrs_for_signal(%Signal{type: "ai.llm.response"} = signal) do
    data = normalize_data(signal.data)

    capture_attrs(signal,
      class: :episodic,
      kind: :assistant_response,
      text: extract_llm_text(data),
      content: data,
      tags: ["ai", "llm", signal.type]
    )
  end

  defp capture_attrs_for_signal(%Signal{type: "ai.tool.result"} = signal) do
    data = normalize_data(signal.data)
    tool_name = pick(data, :tool_name) || pick(data, :name) || "tool"

    capture_attrs(signal,
      class: :episodic,
      kind: :tool_result,
      text: "#{tool_name} result",
      content: data,
      tags: ["ai", "tool", tool_name, signal.type]
    )
  end

  defp capture_attrs_for_signal(%Signal{} = signal) do
    capture_attrs(signal,
      class: :working,
      kind: :signal_event,
      text: signal.type,
      content: normalize_data(signal.data),
      tags: ["signal", signal.type]
    )
  end

  defp capture_attrs(signal, opts) do
    %{
      class: Keyword.fetch!(opts, :class),
      kind: Keyword.fetch!(opts, :kind),
      text: Keyword.fetch!(opts, :text),
      content: Keyword.fetch!(opts, :content),
      tags: Keyword.fetch!(opts, :tags),
      source: signal.source,
      observed_at: signal_timestamp(signal),
      metadata: base_metadata(signal)
    }
  end

  defp resolve_namespace_by_mode(_agent, config, :shared) do
    shared = Helpers.normalize_optional_string(Helpers.map_get(config, :shared_namespace)) || "default"
    {:ok, "shared:" <> shared}
  end

  defp resolve_namespace_by_mode(agent, _config, _mode) do
    case Helpers.target_id(agent) do
      id when is_binary(id) and id != "" -> {:ok, "agent:" <> id}
      _ -> {:error, :namespace_required}
    end
  end

  @spec maybe_apply_capture_rule(map(), String.t(), map()) :: map() | :skip
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
          Map.merge(metadata, Helpers.map_get(rule, :metadata, %{}))
        end)

      _ ->
        base
    end
  end

  defp maybe_apply_capture_rule(base, _signal_type, _rules), do: base

  @spec maybe_override(map(), map(), atom()) :: map()
  defp maybe_override(base, rule, key) do
    value = Helpers.map_get(rule, key)
    if is_nil(value), do: base, else: Map.put(base, key, value)
  end

  @spec merge_tags(map(), map()) :: map()
  defp merge_tags(base, rule) do
    case Helpers.map_get(rule, :tags) do
      tags when is_list(tags) ->
        tags = Enum.map(tags, &to_string/1)
        Map.put(base, :tags, Enum.uniq((base.tags || []) ++ tags))

      _ ->
        base
    end
  end

  @spec extract_llm_text(map()) :: String.t() | nil
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

  @spec signal_timestamp(Signal.t()) :: integer()
  defp signal_timestamp(%Signal{time: nil}), do: System.system_time(:millisecond)

  defp signal_timestamp(%Signal{time: time}) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _offset} -> DateTime.to_unix(dt, :millisecond)
      _ -> System.system_time(:millisecond)
    end
  end

  defp signal_timestamp(_), do: System.system_time(:millisecond)

  @spec base_metadata(Signal.t()) :: map()
  defp base_metadata(%Signal{} = signal) do
    %{
      signal_id: signal.id,
      signal_type: signal.type,
      subject: signal.subject
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @spec normalize_data(term()) :: map()
  defp normalize_data(%{} = data), do: data
  defp normalize_data(nil), do: %{}
  defp normalize_data(data), do: %{value: data}

  @spec signal_matches_any?(String.t(), [String.t()]) :: boolean()
  defp signal_matches_any?(_type, []), do: false

  defp signal_matches_any?(type, patterns) when is_binary(type) and is_list(patterns) do
    Enum.any?(patterns, &signal_type_matches?(type, &1))
  end

  @spec signal_type_matches?(String.t(), String.t()) :: boolean()
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

  @spec pick(map(), atom()) :: term()
  defp pick(map, key), do: Helpers.map_get(map, key)

  @spec safe_existing_atom(String.t()) :: atom() | nil
  defp safe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp safe_existing_atom(_), do: nil

  defp normalize_provider_input(nil, provider_opts), do: {Basic, provider_opts}

  defp normalize_provider_input(%ProviderRef{} = provider_ref, provider_opts) do
    %ProviderRef{provider_ref | opts: Keyword.merge(provider_ref.opts, provider_opts)}
  end

  defp normalize_provider_input({provider, embedded_opts}, provider_opts)
       when is_atom(provider) and is_list(embedded_opts) do
    {provider, Keyword.merge(embedded_opts, provider_opts)}
  end

  defp normalize_provider_input(provider, provider_opts), do: {provider, provider_opts}

  defp maybe_enrich_basic_provider_ref(%ProviderRef{module: Basic} = provider_ref, namespace, store) do
    %{provider_ref | opts: enrich_basic_provider_opts(provider_ref.opts, namespace, store)}
  end

  defp maybe_enrich_basic_provider_ref(provider_ref, _namespace, _store), do: provider_ref

  defp enrich_basic_provider_opts(opts, namespace, store) do
    opts
    |> Helpers.put_opt_if_missing(:namespace, namespace)
    |> Helpers.put_opt_if_missing(:store, store)
  end

  defp normalize_provider_opts(opts) when is_list(opts), do: opts
  defp normalize_provider_opts(_opts), do: []
end
