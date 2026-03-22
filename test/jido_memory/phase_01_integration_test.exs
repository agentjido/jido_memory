defmodule Jido.Memory.Phase01IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Plugin
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.ProviderBootstrap
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Query
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime
  alias Jido.Memory.Support.ExternalProvider

  defmodule BrokenExternalProvider do
    def validate_config(_opts), do: :ok
  end

  setup_all do
    Code.require_file(Path.expand("../../examples/external_provider_agent.exs", __DIR__))
    :ok
  end

  test "the same plugin workflow succeeds with built-in and external providers" do
    cases = [
      {"basic", %{provider: ProviderFixtures.basic_provider("phase01_basic")}, Basic, "basic external interop flow"},
      {"tiered", %{provider: ProviderFixtures.tiered_provider("phase01_tiered")}, Tiered,
       "tiered external interop flow"},
      {"external",
       %{
         provider: :external_demo,
         provider_aliases: %{external_demo: ExternalProvider},
         provider_opts: [
           store: ProviderFixtures.unique_store("phase01_external_store"),
           namespace: "provider:phase01-external"
         ]
       }, ExternalProvider, "external external interop flow"}
    ]

    Enum.each(cases, fn {agent_suffix, config, expected_provider, text} ->
      agent = mounted_agent("phase01-#{agent_suffix}", config)

      assert {:ok, %Record{id: id}} =
               Runtime.remember(agent, ProviderFixtures.important_attrs(text), [])

      assert {:ok, [%Record{id: ^id}]} =
               Runtime.retrieve(agent, %{text_contains: text, order: :asc}, [])

      assert {:ok, capabilities} = Runtime.capabilities(agent, [])
      assert capabilities.core == true

      assert {:ok, %{provider: ^expected_provider}} = Runtime.info(agent, [:provider], [])
    end)
  end

  test "invalid external providers fail before dispatch with compatibility-safe results" do
    assert {:error, :invalid_provider_aliases} =
             Plugin.mount(%{id: "phase01-invalid-alias"}, %{
               provider: :external_demo,
               provider_aliases: %{external_demo: "bad"}
             })

    assert {:error, {:invalid_provider, BrokenExternalProvider}} =
             Runtime.remember(
               %{id: "phase01-invalid-provider"},
               %{class: :episodic, text: "x"},
               provider: :broken_demo,
               provider_aliases: %{broken_demo: BrokenExternalProvider}
             )
  end

  test "built-in providers remain unchanged when no external bootstrap is configured" do
    assert {:ok, []} = ProviderBootstrap.child_specs(ProviderFixtures.basic_provider("phase01_boot_basic"))
    assert {:ok, []} = ProviderBootstrap.child_specs(ProviderFixtures.tiered_provider("phase01_boot_tiered"))
  end

  test "external bootstrap helpers behave predictably when providers expose child specs" do
    assert {:ok, child_specs} =
             ProviderBootstrap.child_specs(
               :external_demo,
               provider_aliases: %{external_demo: ExternalProvider},
               store: ProviderFixtures.unique_store("phase01_boot_external"),
               namespace: "provider:phase01-bootstrap"
             )

    assert length(child_specs) == 1

    assert {:ok, description} =
             ProviderBootstrap.describe(
               :external_demo,
               provider_aliases: %{external_demo: ExternalProvider},
               store: ProviderFixtures.unique_store("phase01_boot_external_desc"),
               namespace: "provider:phase01-bootstrap"
             )

    assert description.provider == ExternalProvider
    assert description.ownership == :caller
    assert description.provider_meta.bootstrap.ownership == :caller
  end

  test "docs-backed external provider example executes successfully" do
    prefix = "docs_external_#{System.unique_integer([:positive])}"
    example_agent = Module.concat([Example, ExternalProviderAgent])

    assert {:ok,
            %{
              plugin_state: %{provider_aliases: %{external_demo: Example.ExternalProvider}},
              record: %Record{},
              records: [%Record{} | _],
              bootstrap: %{ownership: :caller}
            }} =
             example_agent.run_demo("docs-external-agent", prefix)
  end

  test "query extensions survive runtime dispatch and tiered explanation parity" do
    provider = ProviderFixtures.tiered_provider("phase01_query_ext")
    agent = mounted_agent("phase01-query-ext", %{provider: provider})

    assert {:ok, %Record{id: short_id}} =
             Runtime.remember(
               agent,
               %{class: :episodic, kind: :event, text: "phase01 query extension short", tier: :short},
               []
             )

    assert {:ok, %Record{id: mid_id}} =
             Runtime.remember(
               agent,
               %{class: :semantic, kind: :fact, text: "phase01 query extension mid", tier: :mid, importance: 1.0},
               []
             )

    assert {:ok, query} =
             Query.new(%{
               text_contains: "phase01 query extension",
               query_extensions: %{tiered: %{tiers: [:mid]}}
             })

    assert query.extensions == %{tiered: %{tiers: [:mid]}}

    assert {:ok, [%Record{id: ^mid_id}]} = Runtime.retrieve(agent, query, [])

    assert {:ok, explanation} = Runtime.explain_retrieval(agent, query, [])
    assert explanation.extensions.tiered.requested_tiers == [:mid]
    assert explanation.extensions.tiered.participating_tiers == [:mid]
    assert Enum.map(explanation.results, & &1.id) == [mid_id]
    refute short_id == mid_id
  end

  defp mounted_agent(agent_id, config) do
    assert {:ok, plugin_state} = Plugin.mount(%{id: agent_id}, config)
    %{id: agent_id, state: %{__memory__: plugin_state}}
  end
end
