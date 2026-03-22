defmodule Jido.Memory.Phase04IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Plugin
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime
  alias Jido.Memory.Support.ExternalProvider

  setup_all do
    Code.require_file(Path.expand("../../examples/basic_provider_agent.exs", __DIR__))
    Code.require_file(Path.expand("../../examples/tiered_provider_agent.exs", __DIR__))
    Code.require_file(Path.expand("../../examples/postgres_tiered_agent.exs", __DIR__))
    :ok
  end

  test "the same core memory workflow succeeds across the supported provider matrix" do
    cases = [
      {ProviderFixtures.basic_provider("phase04_basic"), Basic, "phase04 basic workflow"},
      {ProviderFixtures.tiered_provider("phase04_tiered"), Tiered, "phase04 tiered workflow"},
      {ProviderFixtures.postgres_tiered_provider("phase04_tiered_pg"), Tiered, "phase04 tiered postgres workflow"},
      {{ExternalProvider,
        [store: ProviderFixtures.unique_store("phase04_external"), namespace: "provider:phase04-external"]},
       ExternalProvider, "phase04 external workflow"}
    ]

    Enum.each(cases, fn {provider, expected_provider, text} ->
      agent = mounted_agent("phase04-agent-#{System.unique_integer([:positive])}", %{provider: provider})

      assert {:ok, %Record{id: id}} =
               Runtime.remember(agent, ProviderFixtures.important_attrs(text), [])

      assert {:ok, [%Record{id: ^id}]} =
               Runtime.retrieve(agent, %{text_contains: text, order: :asc}, [])

      assert {:ok, %{provider: ^expected_provider}} = Runtime.info(agent, [:provider], [])
    end)
  end

  test "Tiered explainability and durable long-term promotion stay correct under the accepted backend matrix" do
    for provider <- [
          ProviderFixtures.tiered_provider("phase04_tiered_matrix"),
          ProviderFixtures.postgres_tiered_provider("phase04_tiered_pg_matrix")
        ] do
      agent = mounted_agent("phase04-tiered-agent-#{System.unique_integer([:positive])}", %{provider: provider})

      assert {:ok, %Record{id: id}} =
               Runtime.remember(
                 agent,
                 ProviderFixtures.important_attrs("phase04 explain durable memory", %{tier: :mid}),
                 []
               )

      assert {:ok, explanation} =
               Runtime.explain_retrieval(
                 agent,
                 %{text_contains: "phase04 explain durable", tiers: [:short, :mid, :long]},
                 []
               )

      assert explanation.provider == Tiered
      assert explanation.result_count >= 1
      assert Enum.any?(explanation.results, &(&1.id == id and &1.tier == :mid))

      assert {:ok, %{promoted_to_long: 1}} = Runtime.consolidate(agent, tier: :mid)
      assert {:ok, %Record{id: ^id}} = Runtime.get(agent, id, tier: :long)
    end
  end

  test "unsupported capabilities and compatibility paths remain stable" do
    basic_agent =
      mounted_agent("phase04-basic-compat", %{provider: ProviderFixtures.basic_provider("phase04_basic_compat")})

    legacy_tiered_agent =
      mounted_agent("phase04-tiered-compat", %{provider: ProviderFixtures.tiered_provider("phase04_tiered_compat")})

    assert {:ok, %Record{id: basic_id}} =
             Runtime.remember(basic_agent, ProviderFixtures.important_attrs("phase04 basic compat"), [])

    assert {:ok, [%Record{id: ^basic_id}]} = Runtime.recall(basic_agent, %{text_contains: "phase04 basic compat"})
    assert {:error, {:unsupported_capability, :consolidate}} = Runtime.consolidate(basic_agent, [])

    assert {:error, {:unsupported_capability, :explain_retrieval}} =
             Runtime.explain_retrieval(basic_agent, %{text_contains: "x"}, [])

    assert {:ok, %Record{id: tiered_id}} =
             Runtime.remember(legacy_tiered_agent, ProviderFixtures.important_attrs("phase04 tiered compat"), [])

    assert {:ok, [%Record{id: ^tiered_id}]} =
             Runtime.recall(legacy_tiered_agent, %{text_contains: "phase04 tiered compat"})
  end

  test "published guides and release notes match the tested follow-on architecture" do
    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/docs/guides/follow_on_acceptance_matrix.md") =~
             "Built-in `:tiered` with Postgres long-term"

    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/docs/guides/durable_long_term_storage.md") =~
             "Postgres is the first supported durable backend"

    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/docs/guides/external_providers.md") =~
             "External-provider interop is opt-in"

    assert File.read!("/Users/Pascal/code/agentjido/jido_memory/CHANGELOG.md") =~
             "Built-in `Jido.Memory.LongTermStore.Postgres`"

    basic_example = Module.concat([Example, BasicProviderAgent])
    tiered_example = Module.concat([Example, TieredProviderAgent])
    postgres_example = Module.concat([Example, PostgresTieredAgent])

    assert {:ok, %{record: %Record{}, records: [%Record{} | _]}} =
             basic_example.run_demo("phase04-docs-basic", "phase04_docs_basic")

    assert {:ok,
            %{
              record: %Record{},
              explanation: %{provider: Tiered},
              lifecycle_snapshot: %{totals: %{promoted: 1, skipped: 1}}
            }} =
             tiered_example.run_demo("phase04-docs-tiered", "phase04_docs_tiered")

    assert {:ok,
            %{
              record: %Record{},
              lifecycle_result: %{promoted_to_long: 1},
              long_record: %Record{}
            }} =
             postgres_example.run_demo("phase04-docs-postgres", "phase04_docs_postgres")
  end

  defp mounted_agent(agent_id, config) do
    assert {:ok, plugin_state} = Plugin.mount(%{id: agent_id}, config)
    %{id: agent_id, state: %{__memory__: plugin_state}}
  end
end
