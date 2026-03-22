defmodule Jido.Memory.Mem0Phase04IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Plugin
  alias Jido.Memory.Provider.Mem0
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime

  test "provider-direct feedback and history stay deterministic for scoped Mem0 memory" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase04_integration_feedback"),
         namespace: "agent:mem0-phase04-integration-feedback"
       ]}

    target = %{id: "mem0-phase04-integration-feedback-agent"}

    assert {:ok, summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "I live in Denver."}]},
               provider: provider,
               user_id: "phase04-user",
               now: 100
             )

    [record_id] = summary.created_ids

    assert {:ok, feedback} =
             Mem0.feedback(
               target,
               record_id,
               %{status: :useful, note: "keep this memory"},
               provider: provider,
               user_id: "phase04-user",
               now: 200
             )

    assert feedback.feedback.status == :useful

    assert {:ok, history} =
             Mem0.history(
               target,
               provider: provider,
               user_id: "phase04-user",
               record_id: record_id
             )

    assert Enum.map(history.events, & &1.event_type) == [:feedback, :ingest_add]
    assert hd(history.events).details[:note] == "keep this memory"
  end

  test "provider-direct export and maintenance controls work without widening runtime routes" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase04_integration_export"),
         namespace: "agent:mem0-phase04-integration-export"
       ]}

    target = %{id: "mem0-phase04-integration-export-agent"}

    assert {:ok, rerun_result} =
             Mem0.rerun_reconciliation(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Elixir."}]},
               provider: provider,
               user_id: "phase04-export-user",
               now: 100
             )

    assert rerun_result.maintenance_mode == :rerun

    assert {:ok, %Record{id: direct_id}} =
             Runtime.remember(
               target,
               %{class: :episodic, kind: :note, text: "phase04 direct note"},
               provider: provider,
               user_id: "phase04-export-user",
               now: 150
             )

    assert {:ok, export} =
             Mem0.export(
               target,
               provider: provider,
               user_id: "phase04-export-user",
               include_history: true
             )

    assert export.count == 2
    assert Enum.any?(export.records, &(&1.id == direct_id))
    assert export.history_count >= 2

    assert {:ok, summary} =
             Mem0.refresh_summary(
               target,
               provider: provider,
               user_id: "phase04-export-user"
             )

    assert summary.totals.records == 2
    assert summary.history_events.ingest_add == 1
    assert summary.history_events.remember == 1
  end

  test "shared runtime and plugin surfaces stay selective for Mem0 advanced operations" do
    provider = ProviderFixtures.mem0_provider("mem0_phase04_boundary")
    target = %{id: "mem0-phase04-boundary-agent"}

    assert {:ok, info} = Runtime.info(target, [:advanced_operations, :surface_boundary], provider: provider)
    assert info.advanced_operations.feedback.access == :provider_direct

    assert info.surface_boundary.provider_direct == [
             :feedback,
             :history,
             :export,
             :refresh_summary,
             :rerun_reconciliation
           ]

    refute function_exported?(Runtime, :feedback, 3)
    refute function_exported?(Runtime, :history, 2)
    refute function_exported?(Runtime, :export, 2)
    refute function_exported?(Runtime, :refresh_summary, 2)
    refute function_exported?(Runtime, :rerun_reconciliation, 3)

    assert Enum.map(Plugin.signal_routes(%{}), &elem(&1, 0)) == ["remember", "retrieve", "recall", "forget"]
  end

  test "existing built-in and external providers remain unaffected" do
    basic_provider = ProviderFixtures.basic_provider("mem0_phase04_basic")
    external_provider = ProviderFixtures.external_provider("mem0_phase04_external")

    assert ProviderContract.supports?(basic_provider, [:ingestion, :batch]) == false
    assert ProviderContract.supports?(external_provider, [:ingestion, :batch]) == false

    basic_target = %{id: "mem0-phase04-basic-target"}

    assert {:ok, %Record{id: basic_id}} =
             Runtime.remember(
               basic_target,
               %{class: :semantic, kind: :fact, text: "phase04 basic unaffected"},
               provider: basic_provider
             )

    assert {:ok, [%Record{id: ^basic_id, metadata: metadata}]} =
             Runtime.retrieve(
               basic_target,
               %{text_contains: "phase04 basic unaffected", classes: [:semantic]},
               provider: basic_provider
             )

    refute Map.has_key?(metadata, "mem0")

    assert {:error, {:unsupported_capability, :explain_retrieval}} =
             Runtime.explain_retrieval(%{id: "basic"}, %{text_contains: "x"}, provider: basic_provider)
  end
end
