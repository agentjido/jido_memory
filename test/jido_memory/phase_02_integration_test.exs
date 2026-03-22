defmodule Jido.Memory.Phase02IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Plugin
  alias Jido.Memory.PluginSupport
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime

  setup_all do
    Code.require_file(Path.expand("../../examples/tiered_provider_agent.exs", __DIR__))
    :ok
  end

  test "Runtime.explain_retrieval returns tier-aware explanations and Basic stays unsupported" do
    tiered_agent = mounted_agent("phase02-explain-tiered", ProviderFixtures.tiered_provider("phase02_explain_tiered"))
    basic_agent = mounted_agent("phase02-explain-basic", ProviderFixtures.basic_provider("phase02_explain_basic"))

    assert {:ok, %Record{id: short_id}} =
             Runtime.remember(
               tiered_agent,
               %{class: :episodic, kind: :event, text: "phase02 explain short memory"},
               []
             )

    assert {:ok, %Record{id: mid_id}} =
             Runtime.remember(
               tiered_agent,
               %{class: :semantic, kind: :fact, text: "phase02 explain mid memory", importance: 1.0, tier: :mid},
               []
             )

    query = %{text_contains: "phase02 explain", tiers: [:short, :mid, :long], order: :asc}

    assert {:ok, records} = Runtime.retrieve(tiered_agent, query, [])
    assert {:ok, explanation} = Runtime.explain_retrieval(tiered_agent, query, [])

    assert ProviderContract.canonical_explanation?(explanation)
    assert explanation.provider == Tiered
    assert Enum.map(explanation.results, & &1.id) == Enum.map(records, & &1.id)
    assert short_id in Enum.map(records, & &1.id)
    assert mid_id in Enum.map(records, & &1.id)

    assert Enum.all?(explanation.results, fn result ->
             result.tier in [:short, :mid] and :text_contains in result.matched_on
           end)

    assert explanation.extensions.tiered.requested_tiers == [:short, :mid, :long]
    assert MapSet.new(explanation.extensions.tiered.participating_tiers) == MapSet.new([:short, :mid])

    assert {:error, {:unsupported_capability, :explain_retrieval}} =
             Runtime.explain_retrieval(basic_agent, %{text_contains: "missing"}, [])
  end

  test "shared runtime and plugin surfaces stay selective while provider-direct lanes stay discoverable" do
    basic_provider = ProviderFixtures.basic_provider("phase02_boundary_basic")
    tiered_provider = ProviderFixtures.tiered_provider("phase02_boundary_tiered")

    refute function_exported?(Runtime, :ingest, 3)
    refute function_exported?(Runtime, :put_vault_entry, 3)
    refute function_exported?(Runtime, :get_vault_entry, 3)
    refute function_exported?(Runtime, :forget_vault_entry, 3)

    signal_types = Enum.map(PluginSupport.signal_routes(), &elem(&1, 0))
    refute "ingest" in signal_types
    refute "vault_get" in signal_types
    refute "vault_put" in signal_types
    refute "vault_forget" in signal_types

    assert ProviderContract.supports?(basic_provider, [:ingestion, :batch]) == false
    assert ProviderContract.supports?(tiered_provider, [:ingestion, :batch]) == false
    assert ProviderContract.supports?(basic_provider, [:governance, :protected_memory]) == false
    assert ProviderContract.supports?(tiered_provider, [:governance, :protected_memory]) == false

    assert {:ok, %{provider: Basic}} =
             Runtime.info(%{id: "phase02-boundary-basic"}, [:provider], provider: basic_provider)

    assert {:ok, %{provider: Tiered}} =
             Runtime.info(%{id: "phase02-boundary-tiered"}, [:provider], provider: tiered_provider)
  end

  test "consolidation rationale and lifecycle inspection reflect actual tier transitions" do
    agent = mounted_agent("phase02-lifecycle-agent", ProviderFixtures.tiered_provider("phase02_lifecycle"))

    assert {:ok, %Record{id: promoted_id}} =
             Runtime.remember(
               agent,
               ProviderFixtures.important_attrs("phase02 lifecycle promoted"),
               []
             )

    assert {:ok, %Record{id: skipped_id}} =
             Runtime.remember(
               agent,
               %{class: :working, kind: :event, text: "phase02 lifecycle skipped", importance: 0.1},
               []
             )

    assert {:ok, lifecycle_result} = Runtime.consolidate(agent, tier: :short)

    assert lifecycle_result.tier_results.short.promoted == 1
    assert lifecycle_result.tier_results.short.skipped == 1

    decisions = Map.new(lifecycle_result.tier_results.short.decisions, &{&1.id, &1})
    assert decisions[promoted_id].decision == :promoted
    assert decisions[skipped_id].decision == :skipped
    assert decisions[skipped_id].reason == :below_threshold

    assert {:ok, lifecycle_snapshot} = Tiered.inspect_lifecycle(agent, tiers: [:short, :mid, :long])

    assert lifecycle_snapshot.current_tiers.short == 1
    assert lifecycle_snapshot.current_tiers.mid == 1
    assert lifecycle_snapshot.current_tiers.long == 0
    assert lifecycle_snapshot.totals.promoted == 1
    assert lifecycle_snapshot.totals.skipped == 1
    assert lifecycle_snapshot.recent_outcomes.short.promoted == 1
    assert lifecycle_snapshot.recent_outcomes.short.skipped == 1
    assert lifecycle_snapshot.recent_outcomes.short.skipped_reasons.below_threshold == 1

    snapshot_records = Map.new(lifecycle_snapshot.records, &{&1.id, &1})
    assert snapshot_records[promoted_id].tier == :mid
    assert snapshot_records[skipped_id].tier == :short
  end

  test "docs-backed Tiered inspection example executes successfully" do
    prefix = "docs_tiered_phase02_#{System.unique_integer([:positive])}"

    assert {:ok,
            %{
              record: %Record{},
              skipped_record: %Record{},
              explanation: %{provider: Tiered, result_count: 1},
              lifecycle_result: %{tier_results: %{short: %{promoted: 1, skipped: 1}}},
              lifecycle_snapshot: %{totals: %{promoted: 1, skipped: 1}},
              promoted_record: %Record{}
            }} = Example.TieredProviderAgent.run_demo("docs-phase02-tiered-agent", prefix)
  end

  defp mounted_agent(agent_id, provider) do
    assert {:ok, plugin_state} = Plugin.mount(%{id: agent_id}, %{provider: provider})
    %{id: agent_id, state: %{__memory__: plugin_state}}
  end
end
