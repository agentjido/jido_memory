require Jido.Memory.Actions.Forget
require Jido.Memory.Actions.Recall
require Jido.Memory.Actions.Remember

defmodule Jido.Memory.ETSPlugin do
  @moduledoc """
  ETS-backed memory plugin for Jido agents.

  This plugin owns `:__memory__` state and keeps only lightweight runtime
  metadata in agent state while records live in ETS.
  """

  alias Jido.Signal
  alias Jido.Memory.Actions.{Forget, Recall, Remember}
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
                  auto_capture: Zoi.boolean() |> Zoi.default(true),
                  capture_signal_patterns:
                    Zoi.list(Zoi.string())
                    |> Zoi.default(@default_capture_patterns),
                  capture_rules: Zoi.map() |> Zoi.default(%{})
                })

  @config_schema Zoi.object(%{
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

  use Jido.Plugin,
    name: "memory",
    state_key: :__memory__,
    actions: [Remember, Recall, Forget],
    schema: @state_schema,
    config_schema: @config_schema,
    singleton: true,
    description: "ETS-backed memory plugin with structured retrieval and auto-capture.",
    capabilities: [:memory]

  @impl Jido.Plugin
  def mount(agent, config) do
    with {:ok, namespace} <- resolve_namespace(agent, config),
         {:ok, {store_mod, store_opts}} <- resolve_store(config),
         :ok <- store_mod.ensure_ready(store_opts) do
      {:ok,
       %{
         namespace: namespace,
         store: {store_mod, store_opts},
         auto_capture: map_get(config, :auto_capture, true),
         capture_signal_patterns:
           map_get(config, :capture_signal_patterns, @default_capture_patterns),
         capture_rules: map_get(config, :capture_rules, %{})
       }}
    end
  end

  @impl Jido.Plugin
  def signal_routes(_config) do
    [
      {"remember", Remember},
      {"recall", Recall},
      {"forget", Forget}
    ]
  end

  @impl Jido.Plugin
  def handle_signal(%Signal{} = signal, context) do
    plugin_state =
      context
      |> map_get(:agent, %{})
      |> map_get(:state, %{})
      |> map_get(:__memory__, %{})

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

  @impl Jido.Plugin
  def on_checkpoint(_plugin_state, _context), do: :keep

  @impl Jido.Plugin
  def on_restore(pointer, _context) when is_map(pointer), do: {:ok, pointer}
  def on_restore(_pointer, _context), do: {:ok, nil}

  @spec resolve_store(map()) :: {:ok, {module(), keyword()}} | {:error, term()}
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

  @spec resolve_namespace(map(), map()) :: {:ok, String.t()} | {:error, term()}
  defp resolve_namespace(agent, config) do
    explicit = map_get(config, :namespace)

    if is_binary(explicit) and String.trim(explicit) != "" do
      {:ok, String.trim(explicit)}
    else
      mode = map_get(config, :namespace_mode, :per_agent)

      case mode do
        :shared ->
          shared = map_get(config, :shared_namespace)

          shared =
            if is_binary(shared) and String.trim(shared) != "" do
              String.trim(shared)
            else
              "default"
            end

          {:ok, "shared:" <> shared}

        _ ->
          case map_get(agent, :id) do
            id when is_binary(id) and id != "" -> {:ok, "agent:" <> id}
            _ -> {:error, :namespace_required}
          end
      end
    end
  end

  @spec build_capture_attrs(Signal.t(), map()) :: map() | :skip
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
          Map.merge(metadata, map_get(rule, :metadata, %{}))
        end)

      _ ->
        base
    end
  end

  defp maybe_apply_capture_rule(base, _signal_type, _rules), do: base

  @spec maybe_override(map(), map(), atom()) :: map()
  defp maybe_override(base, rule, key) do
    value = map_get(rule, key)
    if is_nil(value), do: base, else: Map.put(base, key, value)
  end

  @spec merge_tags(map(), map()) :: map()
  defp merge_tags(base, rule) do
    case map_get(rule, :tags) do
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
  defp pick(map, key), do: map_get(map, key)

  @spec map_get(map(), atom(), term()) :: term()
  defp map_get(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  @spec safe_existing_atom(String.t()) :: atom() | nil
  defp safe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp safe_existing_atom(_), do: nil
end
