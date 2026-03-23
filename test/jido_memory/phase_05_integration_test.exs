defmodule Jido.Memory.Phase05IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Plugin
  alias Jido.Memory.PluginSupport
  alias Jido.Memory.Provider.Mirix
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime

  setup_all do
    Code.require_file(Path.expand("../../examples/basic_provider_agent.exs", __DIR__))
    Code.require_file(Path.expand("../../examples/tiered_provider_agent.exs", __DIR__))
    Code.require_file(Path.expand("../../examples/mirix_provider_agent.exs", __DIR__))
    :ok
  end

  test "the same plugin workflow succeeds with built-in Basic, Tiered, and Mirix providers" do
    for {provider, text} <- [
          {ProviderFixtures.basic_provider("phase05_basic"), "basic workflow memory"},
          {ProviderFixtures.tiered_provider("phase05_tiered"), "tiered workflow memory"},
          {ProviderFixtures.mirix_provider("phase05_mirix"), "mirix workflow memory"}
        ] do
      agent = mounted_agent("workflow-agent", provider)

      assert {:ok, %Record{id: id}} =
               Runtime.remember(agent, ProviderFixtures.important_attrs(text), [])

      assert {:ok, [%Record{id: ^id}]} =
               Runtime.retrieve(agent, %{text_contains: text, order: :asc}, [])

      assert {:ok, true} = Runtime.forget(agent, id, [])
    end
  end

  test "retrieve and recall stay aligned across the overlapping Basic, Tiered, and Mirix query subset" do
    for {provider, text} <- [
          {ProviderFixtures.basic_provider("phase05_parity_basic"), "shared parity memory"},
          {ProviderFixtures.tiered_provider("phase05_parity_tiered"), "shared parity memory"},
          {ProviderFixtures.mirix_provider("phase05_parity_mirix"), "shared parity memory"}
        ] do
      agent = mounted_agent("parity-agent", provider)

      assert {:ok, %Record{id: id}} =
               Runtime.remember(agent, ProviderFixtures.important_attrs(text), [])

      assert {:ok, retrieve_records} = Runtime.retrieve(agent, %{text_contains: text, order: :asc}, [])
      assert {:ok, recall_records} = Runtime.recall(agent, %{text_contains: text, order: :asc})

      assert Enum.map(retrieve_records, & &1.id) == Enum.map(recall_records, & &1.id)
      assert id in Enum.map(recall_records, & &1.id)
    end
  end

  test "explainability surfaces differ across Basic, Tiered, and Mirix" do
    basic_provider = ProviderFixtures.basic_provider("phase05_caps_basic")
    tiered_provider = ProviderFixtures.tiered_provider("phase05_caps_tiered")
    mirix_provider = ProviderFixtures.mirix_provider("phase05_caps_mirix")
    tiered_agent = mounted_agent("capability-agent", tiered_provider)
    mirix_agent = mounted_agent("mirix-capability-agent", mirix_provider)

    assert ProviderContract.supports?(basic_provider, [:lifecycle, :consolidate]) == false
    assert ProviderContract.supports?(tiered_provider, [:lifecycle, :consolidate]) == true
    assert ProviderContract.supports?(mirix_provider, [:retrieval, :explainable]) == true

    assert {:error, {:unsupported_capability, :consolidate}} =
             Runtime.consolidate(%{id: "capability-agent"}, provider: basic_provider)

    assert {:ok, %Record{id: id}} =
             Runtime.remember(
               tiered_agent,
               ProviderFixtures.important_attrs("promote this memory"),
               []
             )

    assert {:ok, %{promoted_to_mid: 1}} = Runtime.consolidate(tiered_agent, tier: :short)
    assert {:ok, %Record{id: ^id}} = Runtime.get(tiered_agent, id, tier: :mid)

    assert {:ok, %Record{id: mirix_id}} =
             Runtime.remember(
               mirix_agent,
               %{class: :semantic, kind: :fact, text: "mirix explainability memory"},
               []
             )

    assert {:ok, explanation} =
             Runtime.explain_retrieval(
               mirix_agent,
               %{text_contains: "mirix explainability", query_extensions: %{mirix: %{memory_types: [:semantic]}}},
               []
             )

    assert explanation.provider == Mirix
    assert explanation.result_count == 1
    assert hd(explanation.results).id == mirix_id
    assert explanation.extensions.mirix.participating_memory_types == [:semantic]
    assert explanation.extensions.mirix.retrieval_plan.selected_memory_types == [:semantic]
    assert Enum.any?(explanation.extensions.mirix.routing_trace, &(&1.step == :select_memory_types))
  end

  test "docs-backed built-in provider examples execute successfully" do
    basic_prefix = "docs_basic_#{System.unique_integer([:positive])}"
    tiered_prefix = "docs_tiered_#{System.unique_integer([:positive])}"
    mirix_prefix = "docs_mirix_#{System.unique_integer([:positive])}"
    basic_example = Module.concat([Example, BasicProviderAgent])
    tiered_example = Module.concat([Example, TieredProviderAgent])
    mirix_example = Module.concat([Example, MirixProviderAgent])

    assert {:ok, %{record: %Record{}, records: [%Record{} | _]}} =
             basic_example.run_demo("docs-basic-agent", basic_prefix)

    assert {:ok, %{record: %Record{}, promoted_record: %Record{}, lifecycle_result: %{promoted_to_mid: 1}}} =
             tiered_example.run_demo("docs-tiered-agent", tiered_prefix)

    assert {:ok,
            %{
              remembered_record: %Record{},
              ingest_result: %{counts_by_memory_type: _},
              explanation: %{extensions: %{mirix: %{retrieval_plan: _}}},
              vault_record: %Record{},
              direct_vault_record: %Record{}
            }} =
             mirix_example.run_demo("docs-mirix-agent", mirix_prefix)
  end

  test "mirix advanced workflows stay provider-direct and the docs reflect the built-in provider matrix" do
    routes = PluginSupport.signal_routes()

    refute Enum.any?(routes, fn {route, _module} ->
             String.contains?(route, "ingest") or String.contains?(route, "vault")
           end)

    refute function_exported?(Runtime, :ingest, 3)

    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/README.md") =~ "`:mirix`"

    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/docs/guides/05_release_support_matrix.md") =~
             "Built-in `:mirix`"

    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/.spec/topology.md") =~ "built-in `:mirix`"
  end

  defp mounted_agent(agent_id, provider) do
    assert {:ok, plugin_state} = Plugin.mount(%{id: agent_id}, %{provider: provider})
    %{id: agent_id, state: %{__memory__: plugin_state}}
  end
end
