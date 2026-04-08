defmodule Jido.Memory.BasicPluginTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.BasicPlugin, as: Plugin
  alias Jido.Memory.{RetrieveResult, Runtime}
  alias Jido.Memory.Store.ETS

  setup do
    Application.ensure_all_started(:jido_signal)
    table = String.to_atom("jido_memory_plugin_test_#{System.unique_integer([:positive])}")
    opts = [table: table]
    assert :ok = ETS.ensure_ready(opts)
    %{store: {ETS, opts}, opts: opts}
  end

  test "mount resolves per-agent namespace and store", %{store: store} do
    assert {:ok, state} =
             Plugin.mount(%{id: "agent-1"}, %{store: store, namespace_mode: :per_agent})

    assert state.namespace == "agent:agent-1"
    assert state.store == store
    assert state.auto_capture == true
    refute Map.has_key?(state, :provider)
    refute Map.has_key?(state, :provider_opts)
  end

  test "mount supports shared namespaces", %{store: store} do
    assert {:ok, state} =
             Plugin.mount(%{id: "agent-2"}, %{
               store: store,
               namespace_mode: :shared,
               shared_namespace: "team"
             })

    assert state.namespace == "shared:team"
  end

  test "signal routes expose explicit memory actions" do
    routes = Plugin.signal_routes(%{})

    assert {"remember", Jido.Memory.Actions.Remember} in routes
    assert {"retrieve", Jido.Memory.Actions.Retrieve} in routes
    assert {"forget", Jido.Memory.Actions.Forget} in routes
  end

  test "handle_signal auto-captures ai and generic configured patterns", %{store: store} do
    {:ok, plugin_state} =
      Plugin.mount(%{id: "agent-cap"}, %{
        store: store,
        capture_signal_patterns: ["ai.react.query", "bt.*"]
      })

    agent = %{id: "agent-cap", state: %{__memory__: plugin_state}}
    context = %{agent: agent}

    signal_query = Jido.Signal.new!("ai.react.query", %{query: "what is memory?"}, source: "/ai")
    signal_bt = Jido.Signal.new!("bt.node.enter", %{node: "root"}, source: "/bt")

    assert {:ok, :continue} = Plugin.handle_signal(signal_query, context)
    assert {:ok, :continue} = Plugin.handle_signal(signal_bt, context)

    assert {:ok, result} = Runtime.retrieve(agent, %{order: :asc})
    records = RetrieveResult.records(result)
    assert Enum.any?(records, &(&1.kind == :user_query))
    assert Enum.any?(records, &(&1.kind == :signal_event and &1.class == :working))
  end

  test "capture rules can skip specific signal types", %{store: store} do
    {:ok, plugin_state} =
      Plugin.mount(%{id: "agent-skip"}, %{
        store: store,
        capture_signal_patterns: ["bt.*"],
        capture_rules: %{"bt.node.enter" => %{skip: true}}
      })

    agent = %{id: "agent-skip", state: %{__memory__: plugin_state}}
    context = %{agent: agent}

    signal_bt = Jido.Signal.new!("bt.node.enter", %{node: "root"}, source: "/bt")

    assert {:ok, :continue} = Plugin.handle_signal(signal_bt, context)
    assert {:ok, %RetrieveResult{hits: []}} = Runtime.retrieve(agent, %{order: :asc})
  end

  test "capture rules can override fields and merge metadata", %{store: store} do
    {:ok, plugin_state} =
      Plugin.mount(%{id: "agent-override"}, %{
        store: store,
        capture_signal_patterns: ["bt.*.enter"],
        capture_rules: %{
          "bt.node.enter" => %{
            class: :episodic,
            kind: :fact,
            text: "entered node",
            tags: ["rule-tag"],
            metadata: %{phase: "entry"}
          }
        }
      })

    agent = %{id: "agent-override", state: %{__memory__: plugin_state}}
    context = %{agent: agent}

    signal = Jido.Signal.new!("bt.node.enter", %{node: "root"}, source: "/bt")

    assert {:ok, :continue} = Plugin.handle_signal(signal, context)
    assert {:ok, result} = Runtime.retrieve(agent, %{order: :asc})
    [record] = RetrieveResult.records(result)
    assert record.class == :episodic
    assert record.kind == :fact
    assert record.text == "entered node"
    assert "rule-tag" in record.tags
    assert record.metadata.phase == "entry"
    assert record.metadata.signal_type == "bt.node.enter"
  end

  test "shared namespace mode defaults to shared:default", %{store: store} do
    assert {:ok, state} =
             Plugin.mount(%{id: "agent-shared-default"}, %{
               store: store,
               namespace_mode: :shared
             })

    assert state.namespace == "shared:default"
  end

  test "checkpoint/restore keep lightweight plugin state" do
    pointer = %{namespace: "agent:x", store: {ETS, [table: :x]}}
    assert :keep = Plugin.on_checkpoint(pointer, %{})
    assert {:ok, restored} = Plugin.on_restore(pointer, %{})
    assert restored.namespace == "agent:x"
    assert restored.store == {ETS, [table: :x]}
    refute Map.has_key?(restored, :provider)
    refute Map.has_key?(restored, :provider_opts)
  end

  test "runtime resolves the basic provider from plugin state", %{store: store} do
    agent = %{
      id: "agent-runtime",
      state: %{
        __memory__: %{
          namespace: "agent:agent-runtime",
          store: store
        }
      }
    }

    assert {:ok, {Jido.Memory.Provider.Basic, provider_opts}} =
             Runtime.resolve_provider(agent, %{}, [])

    assert Keyword.get(provider_opts, :namespace) == "agent:agent-runtime"
    assert Keyword.get(provider_opts, :store) == store
  end
end
