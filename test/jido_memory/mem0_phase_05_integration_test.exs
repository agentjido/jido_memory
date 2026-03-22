defmodule Jido.Memory.Mem0Phase05IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Plugin
  alias Jido.Memory.PluginSupport
  alias Jido.Memory.Provider.Mem0
  alias Jido.Memory.Provider.Mirix
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime
  alias Jido.Memory.Support.ExternalProvider

  setup_all do
    Code.require_file(Path.expand("../../examples/mem0_provider_agent.exs", __DIR__))
    :ok
  end

  test "the same canonical memory workflow succeeds across the supported provider matrix including mem0" do
    run_id = System.unique_integer([:positive])

    cases = [
      {"basic", %{provider: ProviderFixtures.basic_provider("mem0_phase05_basic_#{run_id}")}, "mem0 phase05 basic"},
      {"tiered", %{provider: ProviderFixtures.tiered_provider("mem0_phase05_tiered_#{run_id}")}, "mem0 phase05 tiered"},
      {"mem0", %{provider: ProviderFixtures.mem0_provider("mem0_phase05_mem0_#{run_id}")}, "mem0 phase05 mem0"},
      {"mirix", %{provider: ProviderFixtures.mirix_provider("mem0_phase05_mirix_#{run_id}")}, "mem0 phase05 mirix"},
      {"external",
       %{
         provider: :external_demo,
         provider_aliases: %{external_demo: ExternalProvider},
         provider_opts: [
           store: ProviderFixtures.unique_store("mem0_phase05_external_store_#{run_id}"),
           namespace: "provider:mem0-phase05-external-#{run_id}"
         ]
       }, "mem0 phase05 external"}
    ]

    Enum.each(cases, fn {suffix, config, text} ->
      agent = mounted_agent("mem0-phase05-workflow-#{suffix}-#{run_id}", config)

      assert {:ok, %Record{id: id}} =
               Runtime.remember(agent, ProviderFixtures.important_attrs(text), [])

      assert {:ok, [%Record{id: ^id}]} =
               Runtime.retrieve(agent, %{text_contains: text, order: :asc}, [])

      assert {:ok, true} = Runtime.forget(agent, id, [])
    end)
  end

  test "runtime explainability stays selective and provider-shaped across the supported matrix" do
    run_id = System.unique_integer([:positive])

    basic_provider = ProviderFixtures.basic_provider("mem0_phase05_caps_basic_#{run_id}")
    tiered_provider = ProviderFixtures.tiered_provider("mem0_phase05_caps_tiered_#{run_id}")
    mem0_provider = ProviderFixtures.mem0_provider("mem0_phase05_caps_mem0_#{run_id}")
    mirix_provider = ProviderFixtures.mirix_provider("mem0_phase05_caps_mirix_#{run_id}")

    tiered_agent = mounted_agent("mem0-phase05-tiered-agent-#{run_id}", %{provider: tiered_provider})
    mem0_agent = %{id: "mem0-phase05-mem0-agent-#{run_id}", app_id: "phase05-app"}
    mirix_agent = mounted_agent("mem0-phase05-mirix-agent-#{run_id}", %{provider: mirix_provider})

    assert {:error, {:unsupported_capability, :explain_retrieval}} =
             Runtime.explain_retrieval(%{id: "mem0-phase05-basic"}, %{text_contains: "x"}, provider: basic_provider)

    assert {:ok, %Record{id: tiered_id}} =
             Runtime.remember(
               tiered_agent,
               ProviderFixtures.important_attrs("mem0 phase05 tiered explainability"),
               []
             )

    assert {:ok, tiered_explanation} =
             Runtime.explain_retrieval(
               tiered_agent,
               %{text_contains: "mem0 phase05 tiered", tiers: [:short, :mid, :long]},
               []
             )

    assert tiered_explanation.provider == Tiered
    assert Enum.any?(tiered_explanation.results, &(&1.id == tiered_id))
    assert Map.has_key?(tiered_explanation.extensions, :tiered)

    assert {:ok, _summary} =
             Mem0.ingest(
               mem0_agent,
               %{entries: [%{role: :user, content: "I live in Denver."}]},
               provider: mem0_provider,
               user_id: "phase05-user"
             )

    assert {:ok, mem0_explanation} =
             Runtime.explain_retrieval(
               mem0_agent,
               %{
                 text_contains: "Denver",
                 query_extensions: %{mem0: %{scope: %{user_id: "phase05-user"}, retrieval_mode: :fact_key_first}}
               },
               provider: mem0_provider
             )

    assert mem0_explanation.provider == Mem0
    assert mem0_explanation.extensions.mem0.scope.effective.user_id == "phase05-user"
    assert mem0_explanation.extensions.mem0.retrieval_strategy.mode == :fact_key_first

    assert {:ok, %Record{id: mirix_id}} =
             Runtime.remember(
               mirix_agent,
               %{class: :semantic, kind: :fact, text: "mem0 phase05 mirix explainability"},
               []
             )

    assert {:ok, mirix_explanation} =
             Runtime.explain_retrieval(
               mirix_agent,
               %{
                 text_contains: "mem0 phase05 mirix",
                 query_extensions: %{mirix: %{memory_types: [:semantic]}}
               },
               []
             )

    assert mirix_explanation.provider == Mirix
    assert hd(mirix_explanation.results).id == mirix_id
    assert mirix_explanation.extensions.mirix.participating_memory_types == [:semantic]
  end

  test "mem0 advanced workflows stay provider-direct and align with docs and benchmark hooks" do
    prefix = "mem0_phase05_docs_#{System.unique_integer([:positive])}"
    mem0_example = Module.concat([Example, Mem0ProviderAgent])
    routes = PluginSupport.signal_routes()

    assert {:ok, result} = mem0_example.run_demo("docs-mem0-agent", prefix)
    assert %Record{} = result.remembered_record
    assert is_list(result.ingest_result.created_ids)
    assert result.ingest_result.maintenance.add == 1
    assert match?([%Record{} | _], result.retrieved_records)
    assert result.explanation.extensions.mem0.scope.effective.user_id == "demo-user"
    assert result.explanation.query.extensions.mem0.fact_key == "favorite:language"
    assert result.feedback_result.feedback.status == :useful
    assert match?([_ | _], result.history_result.events)
    assert match?([_ | _], result.export_result.records)

    refute Enum.any?(routes, fn {route, _module} ->
             String.contains?(route, "ingest") or String.contains?(route, "feedback") or
               String.contains?(route, "history") or String.contains?(route, "export")
           end)

    refute function_exported?(Runtime, :ingest, 3)
    refute function_exported?(Runtime, :feedback, 4)
    refute function_exported?(Runtime, :history, 2)
    refute function_exported?(Runtime, :export, 2)

    assert function_exported?(Mem0, :ingest, 3)
    assert function_exported?(Mem0, :feedback, 4)
    assert function_exported?(Mem0, :history, 2)
    assert function_exported?(Mem0, :export, 2)

    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/README.md") =~ "`:mem0`"

    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/docs/guides/follow_on_acceptance_matrix.md") =~
             "Built-in `:mem0`"

    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/.spec/topology.md") =~ "built-in `:mem0`"

    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/.spec/planning/provider_benchmarking/README.md") =~
             "`:mem0`"

    assert File.read!(
             "/Users/Pascal/code/agentjido/jido_memory/.spec/planning/provider_benchmarking/phase-03-provider-specific-scenario-packs.md"
           ) =~ "Mem0"

    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/docs/guides/follow_on_acceptance_matrix.md") =~
             "Benchmarking stays intentionally outside the release gate"
  end

  defp mounted_agent(agent_id, config) do
    assert {:ok, plugin_state} = Plugin.mount(%{id: agent_id}, config)
    %{id: agent_id, state: %{__memory__: plugin_state}}
  end
end
