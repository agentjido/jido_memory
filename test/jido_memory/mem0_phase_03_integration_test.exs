defmodule Jido.Memory.Mem0Phase03IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Provider.Mem0
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime

  test "mem0 retrieves scoped canonical records and explains retrieval hints through the shared runtime" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase03_runtime"),
         namespace: "agent:mem0-phase03-runtime",
         retrieval: [mode: :balanced]
       ]}

    target = %{id: "mem0-phase03-runtime-agent", app_id: "phase03-app"}

    assert {:ok, _summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Elixir."}]},
               provider: provider,
               user_id: "user-a"
             )

    assert {:ok, first_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "I live in Denver."}]},
               provider: provider,
               user_id: "user-b"
             )

    assert {:ok, second_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Erlang."}]},
               provider: provider,
               user_id: "user-b"
             )

    [location_id] = first_summary.created_ids
    [favorite_id] = second_summary.created_ids

    query = %{
      classes: [:semantic],
      query_extensions: %{
        mem0: %{
          scope: %{user_id: "user-b"},
          retrieval_mode: :fact_key_first,
          fact_key: "favorite:language"
        }
      }
    }

    assert {:ok, [%Record{id: ^favorite_id}, %Record{id: ^location_id}]} =
             Runtime.retrieve(target, query, provider: provider)

    assert {:ok, explanation} = Runtime.explain_retrieval(target, query, provider: provider)
    assert ProviderContract.canonical_explanation?(explanation)
    assert explanation.provider == Mem0
    assert explanation.extensions.mem0.scope.effective.user_id == "user-b"
    assert explanation.extensions.mem0.retrieval_strategy.mode == :fact_key_first
    assert hd(explanation.results).ranking_context.fact_key_match == true
  end

  test "mem0 graph augmentation enriches explanation output without replacing canonical results" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase03_graph_runtime"),
         namespace: "agent:mem0-phase03-graph-runtime",
         retrieval: [graph_augmentation: [enabled: true, relationship_limit: 3]]
       ]}

    target = %{id: "mem0-phase03-graph-runtime-agent"}

    assert {:ok, summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Elixir."}]},
               provider: provider,
               user_id: "graph-user"
             )

    [record_id] = summary.created_ids

    base_query = %{
      classes: [:semantic],
      query_extensions: %{mem0: %{scope: %{user_id: "graph-user"}}}
    }

    graph_query = %{
      classes: [:semantic],
      query_extensions: %{
        mem0: %{scope: %{user_id: "graph-user"}, graph: %{enabled: true, entity_focus: ["favorite:language"]}}
      }
    }

    assert {:ok, [%Record{id: ^record_id}]} = Runtime.retrieve(target, base_query, provider: provider)
    assert {:ok, [%Record{id: ^record_id}]} = Runtime.retrieve(target, graph_query, provider: provider)

    assert {:ok, explanation} = Runtime.explain_retrieval(target, graph_query, provider: provider)
    assert explanation.extensions.mem0.graph.enabled == true
    assert explanation.extensions.mem0.graph.relationship_count == 1
    assert Enum.any?(explanation.extensions.mem0.graph.entities, &(&1.type == :fact_key))
  end

  test "mem0 graph augmentation can be disabled cleanly" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase03_graph_disabled_runtime"),
         namespace: "agent:mem0-phase03-graph-disabled-runtime"
       ]}

    target = %{id: "mem0-phase03-graph-disabled-runtime-agent"}

    assert {:ok, _summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "I live in Denver."}]},
               provider: provider,
               user_id: "graph-disabled-user"
             )

    query = %{
      classes: [:semantic],
      query_extensions: %{mem0: %{scope: %{user_id: "graph-disabled-user"}}}
    }

    assert {:ok, explanation} = Runtime.explain_retrieval(target, query, provider: provider)
    assert explanation.extensions.mem0.graph.enabled == false
    assert explanation.extensions.mem0.graph.relationships == []
  end

  test "non-mem0 providers remain unaffected by mem0 graph query extensions" do
    basic_provider = ProviderFixtures.basic_provider("mem0_phase03_basic")
    basic_target = %{id: "mem0-phase03-basic-target"}

    assert ProviderContract.supports?(basic_provider, [:retrieval, :graph_augmentation]) == false

    assert {:ok, %Record{id: basic_id}} =
             Runtime.remember(
               basic_target,
               %{class: :semantic, kind: :fact, text: "phase03 basic unaffected"},
               provider: basic_provider
             )

    query = %{
      text_contains: "phase03 basic unaffected",
      classes: [:semantic],
      query_extensions: %{mem0: %{graph: %{enabled: true, entity_focus: ["phase03"]}}}
    }

    assert {:ok, [%Record{id: ^basic_id}]} = Runtime.retrieve(basic_target, query, provider: basic_provider)

    tiered_provider = ProviderFixtures.tiered_provider("mem0_phase03_tiered")
    tiered_target = %{id: "mem0-phase03-tiered-target"}

    assert ProviderContract.supports?(tiered_provider, [:retrieval, :graph_augmentation]) == false

    assert {:ok, %Record{id: tiered_id}} =
             Runtime.remember(
               tiered_target,
               %{class: :working, kind: :note, text: "phase03 tiered unaffected"},
               provider: tiered_provider
             )

    tiered_query = %{
      text_contains: "phase03 tiered unaffected",
      classes: [:working],
      query_extensions: %{mem0: %{graph: %{enabled: true, entity_focus: ["phase03"]}}}
    }

    assert {:ok, [%Record{id: ^tiered_id}]} =
             Runtime.retrieve(tiered_target, tiered_query, provider: tiered_provider)

    assert {:ok, tiered_explanation} =
             Runtime.explain_retrieval(tiered_target, tiered_query, provider: tiered_provider)

    assert Map.has_key?(tiered_explanation.extensions, :tiered)
    refute Map.has_key?(tiered_explanation.extensions, :mem0)
  end
end
