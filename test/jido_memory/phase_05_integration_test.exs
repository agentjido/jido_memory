defmodule Jido.Memory.Phase05IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Plugin
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime

  setup_all do
    Code.require_file(Path.expand("../../examples/basic_provider_agent.exs", __DIR__))
    Code.require_file(Path.expand("../../examples/tiered_provider_agent.exs", __DIR__))
    :ok
  end

  test "the same plugin workflow succeeds with built-in Basic and Tiered providers" do
    for {provider, text} <- [
          {ProviderFixtures.basic_provider("phase05_basic"), "basic workflow memory"},
          {ProviderFixtures.tiered_provider("phase05_tiered"), "tiered workflow memory"}
        ] do
      agent = mounted_agent("workflow-agent", provider)

      assert {:ok, %Record{id: id}} =
               Runtime.remember(agent, ProviderFixtures.important_attrs(text), [])

      assert {:ok, [%Record{id: ^id}]} =
               Runtime.retrieve(agent, %{text_contains: text, order: :asc}, [])

      assert {:ok, true} = Runtime.forget(agent, id, [])
    end
  end

  test "retrieve and recall stay aligned across the overlapping Basic and Tiered query subset" do
    for {provider, text} <- [
          {ProviderFixtures.basic_provider("phase05_parity_basic"), "shared parity memory"},
          {ProviderFixtures.tiered_provider("phase05_parity_tiered"), "shared parity memory"}
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

  test "Tiered exposes lifecycle support where Basic reports unsupported capabilities" do
    basic_provider = ProviderFixtures.basic_provider("phase05_caps_basic")
    tiered_provider = ProviderFixtures.tiered_provider("phase05_caps_tiered")
    tiered_agent = mounted_agent("capability-agent", tiered_provider)

    assert ProviderContract.supports?(basic_provider, [:lifecycle, :consolidate]) == false
    assert ProviderContract.supports?(tiered_provider, [:lifecycle, :consolidate]) == true

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
  end

  test "docs-backed built-in provider examples execute successfully" do
    basic_prefix = "docs_basic_#{System.unique_integer([:positive])}"
    tiered_prefix = "docs_tiered_#{System.unique_integer([:positive])}"

    assert {:ok, %{record: %Record{}, records: [%Record{} | _]}} =
             Example.BasicProviderAgent.run_demo("docs-basic-agent", basic_prefix)

    assert {:ok, %{record: %Record{}, promoted_record: %Record{}, lifecycle_result: %{promoted_to_mid: 1}}} =
             Example.TieredProviderAgent.run_demo("docs-tiered-agent", tiered_prefix)
  end

  defp mounted_agent(agent_id, provider) do
    assert {:ok, plugin_state} = Plugin.mount(%{id: agent_id}, %{provider: provider})
    %{id: agent_id, state: %{__memory__: plugin_state}}
  end
end
