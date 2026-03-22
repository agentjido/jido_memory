defmodule Jido.Memory.ETSPluginTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.ETSPlugin, as: Plugin
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.ProviderRef
  alias Jido.Memory.Store.ETS

  setup do
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
    assert {"recall", Jido.Memory.Actions.Recall} in routes
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

    assert {:ok, records} = Jido.Memory.Runtime.recall(agent, %{order: :asc})
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
    assert {:ok, []} = Jido.Memory.Runtime.recall(agent, %{order: :asc})
  end

  test "checkpoint/restore keep lightweight plugin state" do
    pointer = %{namespace: "agent:x", store: {ETS, [table: :x]}}
    assert :keep = Plugin.on_checkpoint(pointer, %{})
    assert {:ok, ^pointer} = Plugin.on_restore(pointer, %{})
  end

  test "mount keeps legacy store-backed state while tracking the Basic provider", %{store: store} do
    assert {:ok, state} =
             Plugin.mount(%{id: "agent-legacy"}, %{store: store, namespace_mode: :per_agent})

    assert state.namespace == "agent:agent-legacy"
    assert state.store == store
    assert %ProviderRef{module: Basic, opts: provider_opts} = state.provider
    assert Keyword.get(provider_opts, :store) == store
    assert Keyword.get(provider_opts, :namespace) == "agent:agent-legacy"
  end
end

defmodule Jido.Memory.PluginTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Actions.Retrieve
  alias Jido.Memory.LongTermStore.ETS, as: LongTermETS
  alias Jido.Memory.Plugin
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.ProviderRef
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store.ETS

  setup do
    table = String.to_atom("jido_memory_provider_plugin_test_#{System.unique_integer([:positive])}")
    opts = [table: table]
    assert :ok = ETS.ensure_ready(opts)
    %{store: {ETS, opts}}
  end

  test "mount defaults to the Basic provider when none is configured", %{store: store} do
    assert {:ok, state} =
             Plugin.mount(%{id: "agent-basic"}, %{store: store, namespace_mode: :per_agent})

    assert %ProviderRef{module: Basic, opts: provider_opts} = state.provider
    assert Keyword.get(provider_opts, :store) == store
    assert state.namespace == "agent:agent-basic"
  end

  test "mount accepts provider bundles in canonical tuple form", %{store: store} do
    provider = {Basic, [store: store, namespace: "provider:tuple"]}

    assert {:ok, state} = Plugin.mount(%{id: "agent-provider"}, %{provider: provider})

    assert %ProviderRef{module: Basic, opts: provider_opts} = state.provider
    assert Keyword.get(provider_opts, :store) == store
    assert Keyword.get(provider_opts, :namespace) == "provider:tuple"
    assert state.namespace == "provider:tuple"
    assert state.store == store
    assert state.auto_capture == true
    assert state.capture_rules == %{}
  end

  test "restore normalizes provider-aware pointers", %{store: store} do
    pointer = %{provider: {Basic, [store: store, namespace: "provider:restore"]}, auto_capture: false}

    assert {:ok, restored} = Plugin.on_restore(pointer, %{})
    assert %ProviderRef{module: Basic, opts: provider_opts} = restored.provider
    assert Keyword.get(provider_opts, :store) == store
    assert Keyword.get(provider_opts, :namespace) == "provider:restore"
    assert restored.auto_capture == false
    assert restored.capture_rules == %{}
  end

  test "mount accepts the built-in Tiered provider and common retrieval actions still work" do
    unique = System.unique_integer([:positive])

    provider =
      {:tiered,
       [
         short_store: {ETS, [table: :"jido_memory_plugin_tiered_short_#{unique}"]},
         mid_store: {ETS, [table: :"jido_memory_plugin_tiered_mid_#{unique}"]},
         long_term_store: {LongTermETS, [store: {ETS, [table: :"jido_memory_plugin_tiered_long_#{unique}"]}]}
       ]}

    assert {:ok, state} = Plugin.mount(%{id: "agent-tiered"}, %{provider: provider})
    assert %ProviderRef{module: Tiered} = state.provider

    agent = %{id: "agent-tiered", state: %{__memory__: state}}

    assert {:ok, %Record{id: id}} =
             Runtime.remember(agent, %{class: :episodic, text: "plugin tiered memory"}, [])

    assert {:ok, [%Record{id: ^id}]} =
             Runtime.retrieve(agent, %{text_contains: "plugin tiered memory"}, [])

    assert {:ok, %{memory_results: [%Record{id: ^id}]}} =
             Retrieve.run(%{text_contains: "plugin tiered memory"}, %{id: "agent-tiered", state: %{__memory__: state}})
  end
end
