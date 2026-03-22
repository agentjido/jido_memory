defmodule Jido.Memory.MirixPhase04IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Provider.Mirix
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime

  test "mirix active retrieval merges typed results and exposes routing traces" do
    provider = ProviderFixtures.mirix_provider("mirix_phase04_integration_retrieval")
    target = %{id: "mirix-phase04-integration-retrieval-#{System.unique_integer([:positive])}"}

    assert {:ok, %Record{id: semantic_id}} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "phase4 integrated retrieval", memory_type: :semantic},
               provider: provider
             )

    assert {:ok, %Record{id: procedural_id}} =
             Runtime.remember(
               target,
               %{class: :procedural, kind: :workflow, text: "phase4 integrated retrieval", memory_type: :procedural},
               provider: provider
             )

    assert {:ok, %Record{id: resource_id}} =
             Runtime.remember(
               target,
               %{class: :working, kind: :document, text: "phase4 integrated retrieval", memory_type: :resource},
               provider: provider
             )

    query = %{
      text_contains: "phase4 integrated retrieval",
      query_extensions: %{mirix: %{memory_types: [:semantic, :procedural, :resource], planner_mode: :focused}}
    }

    assert {:ok, records} = Runtime.retrieve(target, query, provider: provider)
    assert MapSet.new(Enum.map(records, & &1.id)) == MapSet.new([semantic_id, procedural_id, resource_id])

    assert {:ok, explanation} = Runtime.explain_retrieval(target, query, provider: provider)

    assert explanation.provider == Mirix
    assert explanation.result_count == 3
    assert explanation.extensions.mirix.requested_memory_types == [:semantic, :procedural, :resource]

    assert explanation.extensions.mirix.participating_memory_types == [:semantic, :procedural, :resource]

    assert explanation.extensions.mirix.retrieval_plan.planner_mode == :focused
    assert explanation.extensions.mirix.retrieval_plan.selected_memory_types == [:semantic, :procedural, :resource]
    assert [%{name: :primary, strategy: :store_query}] = explanation.extensions.mirix.retrieval_plan.passes

    assert Enum.any?(explanation.extensions.mirix.routing_trace, &(&1.step == :select_memory_types))
    assert Enum.any?(explanation.extensions.mirix.routing_trace, &(&1.step == :query_memory_types))
    assert Enum.all?(explanation.results, &(&1.ranking_context.retrieval_pass == :primary))
  end

  test "mirix direct ingestion and vault flows remain explicit while other providers stay unsupported" do
    mirix_provider = ProviderFixtures.mirix_provider("mirix_phase04_integration_direct")
    basic_provider = ProviderFixtures.basic_provider("mirix_phase04_basic")
    tiered_provider = ProviderFixtures.tiered_provider("mirix_phase04_tiered")
    target = %{id: "mirix-phase04-integration-direct-#{System.unique_integer([:positive])}"}

    refute ProviderContract.supports?(basic_provider, [:ingestion, :batch])
    refute ProviderContract.supports?(tiered_provider, [:ingestion, :batch])
    refute ProviderContract.supports?(basic_provider, [:governance, :protected_memory])
    refute ProviderContract.supports?(tiered_provider, [:governance, :protected_memory])

    assert {:ok, ingest_result} =
             Mirix.ingest(
               target,
               %{
                 entries: [
                   %{modality: :fact, content: "phase4 direct ingestion fact"},
                   %{memory_type: :vault, content: "phase4 skipped vault entry"}
                 ]
               },
               provider: mirix_provider
             )

    assert ingest_result.counts_by_memory_type.semantic == 1
    assert ingest_result.skipped == [:vault_requires_direct_access]

    assert {:ok, [semantic_record]} =
             Runtime.retrieve(
               target,
               %{text_contains: "phase4 direct ingestion", query_extensions: %{mirix: %{memory_types: [:semantic]}}},
               provider: mirix_provider
             )

    assert get_in(semantic_record.metadata, ["mirix", "memory_type"]) == "semantic"

    assert {:ok, %Record{id: vault_id}} =
             Mirix.put_vault_entry(
               target,
               %{kind: :credential, text: "phase4 vault direct"},
               provider: mirix_provider
             )

    assert {:error, :not_found} = Runtime.get(target, vault_id, provider: mirix_provider)
    assert {:ok, %Record{id: ^vault_id}} = Mirix.get_vault_entry(target, vault_id, provider: mirix_provider)
  end
end
