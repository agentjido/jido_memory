defmodule Jido.Memory.MirixProviderTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime

  test "mirix focused planner narrows active retrieval to procedural memory" do
    provider = ProviderFixtures.mirix_provider("mirix_phase04_focused")
    target = %{id: "mirix-phase04-focused-#{System.unique_integer([:positive])}"}

    assert {:ok, %Record{}} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "important durable fact", memory_type: :semantic},
               provider: provider
             )

    assert {:ok, %Record{id: procedural_id}} =
             Runtime.remember(
               target,
               %{
                 class: :procedural,
                 kind: :workflow,
                 text: "workflow for durable onboarding",
                 memory_type: :procedural
               },
               provider: provider
             )

    query = %{
      text_contains: "workflow",
      query_extensions: %{mirix: %{planner_mode: :focused}}
    }

    assert {:ok, [%Record{id: ^procedural_id}]} = Runtime.retrieve(target, query, provider: provider)
    assert {:ok, explanation} = Runtime.explain_retrieval(target, query, provider: provider)

    assert explanation.provider == Jido.Memory.Provider.Mirix
    assert explanation.extensions.mirix.participating_memory_types == [:procedural]
    assert explanation.extensions.mirix.retrieval_plan.planner_mode == :focused
    assert hd(explanation.results).memory_type == :procedural
    assert hd(explanation.results).ranking_context.retrieval_pass == :primary
    assert Enum.any?(explanation.extensions.mirix.routing_trace, &(&1.step == :select_memory_types))
  end

  test "mirix memory_types and resource_scope extensions shape planner selection" do
    provider = ProviderFixtures.mirix_provider("mirix_phase04_resource_scope")
    target = %{id: "mirix-phase04-resource-#{System.unique_integer([:positive])}"}

    assert {:ok, %Record{}} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "shared resource phrase", memory_type: :semantic},
               provider: provider
             )

    assert {:ok, %Record{id: resource_id}} =
             Runtime.remember(
               target,
               %{class: :working, kind: :document, text: "shared resource phrase", memory_type: :resource},
               provider: provider
             )

    query = %{
      text_contains: "shared resource phrase",
      query_extensions: %{mirix: %{memory_types: [:semantic, :resource], resource_scope: :only}}
    }

    assert {:ok, [%Record{id: ^resource_id}]} = Runtime.retrieve(target, query, provider: provider)
    assert {:ok, explanation} = Runtime.explain_retrieval(target, query, provider: provider)

    assert explanation.extensions.mirix.requested_memory_types == [:semantic, :resource]
    assert explanation.extensions.mirix.participating_memory_types == [:resource]
    assert explanation.extensions.mirix.retrieval_plan.selected_memory_types == [:resource]
    assert explanation.extensions.mirix.retrieval_plan.resource_scope == :only
    assert hd(explanation.results).memory_type == :resource
  end
end
