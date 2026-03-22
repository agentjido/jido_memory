defmodule Jido.Memory.FollowOnAcceptanceFixtureTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Plugin
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime
  alias Jido.Memory.Support.ExternalProvider

  test "consumer-level plugin flow works across the supported provider matrix" do
    cases = [
      {"basic", %{provider: ProviderFixtures.basic_provider("follow_on_basic")}, :basic, "follow on basic memory"},
      {"tiered_ets", %{provider: ProviderFixtures.tiered_provider("follow_on_tiered_ets")}, :tiered_ets,
       "follow on tiered ets memory"},
      {"tiered_postgres", %{provider: ProviderFixtures.postgres_tiered_provider("follow_on_tiered_pg")},
       :tiered_postgres, "follow on tiered postgres memory"},
      {"external",
       %{
         provider: :external_demo,
         provider_aliases: %{external_demo: ExternalProvider},
         provider_opts: [
           store: ProviderFixtures.unique_store("follow_on_external_store"),
           namespace: "provider:follow-on-external"
         ]
       }, :external, "follow on external memory"}
    ]

    Enum.each(cases, fn {agent_suffix, config, expected_path, text} ->
      agent = mounted_agent("follow-on-#{agent_suffix}", config)

      assert {:ok, %Record{id: id}} =
               Runtime.remember(agent, ProviderFixtures.important_attrs(text), [])

      assert {:ok, [%Record{id: ^id}]} =
               Runtime.retrieve(agent, %{text_contains: text, order: :asc}, [])

      assert {:ok, capabilities} = Runtime.capabilities(agent, [])

      case expected_path do
        :basic ->
          assert capabilities.retrieval.explainable == false

        :external ->
          assert capabilities.core == true

        _tiered ->
          assert capabilities.retrieval.explainable == true
          assert capabilities.lifecycle.consolidate == true
      end
    end)
  end

  test "acceptance fixture includes Tiered explainability and durable long-term promotion" do
    for {provider, expected_long_tier} <- [
          {ProviderFixtures.tiered_provider("follow_on_tiered_matrix"), :long},
          {ProviderFixtures.postgres_tiered_provider("follow_on_tiered_pg_matrix"), :long}
        ] do
      agent = mounted_agent("follow-on-tiered-matrix", %{provider: provider})

      assert {:ok, %Record{id: id}} =
               Runtime.remember(
                 agent,
                 ProviderFixtures.important_attrs("follow on explainable durable memory", %{tier: :mid}),
                 []
               )

      assert {:ok, explanation} =
               Runtime.explain_retrieval(
                 agent,
                 %{text_contains: "follow on explainable", tiers: [:short, :mid, :long]},
                 []
               )

      assert explanation.provider == Tiered
      assert explanation.result_count == 1
      assert hd(explanation.results).tier == :mid

      assert {:ok, %{promoted_to_long: 1}} = Runtime.consolidate(agent, tier: :mid)
      assert {:ok, %Record{id: ^id}} = Runtime.get(agent, id, tier: expected_long_tier)
    end
  end

  test "unsupported capabilities fail cleanly outside the supported matrix" do
    basic_agent =
      mounted_agent("follow-on-basic-unsupported", %{
        provider: ProviderFixtures.basic_provider("follow_on_basic_unsupported")
      })

    external_agent =
      mounted_agent("follow-on-external-unsupported", %{
        provider: :external_demo,
        provider_aliases: %{external_demo: ExternalProvider},
        provider_opts: [
          store: ProviderFixtures.unique_store("follow_on_external_unsupported"),
          namespace: "provider:follow-on-external-unsupported"
        ]
      })

    assert {:error, {:unsupported_capability, :consolidate}} = Runtime.consolidate(basic_agent, [])

    assert {:error, {:unsupported_capability, :explain_retrieval}} =
             Runtime.explain_retrieval(basic_agent, %{text_contains: "x"}, [])

    assert {:error, {:unsupported_capability, :consolidate}} = Runtime.consolidate(external_agent, [])

    assert {:error, {:unsupported_capability, :explain_retrieval}} =
             Runtime.explain_retrieval(external_agent, %{text_contains: "x"}, [])
  end

  defp mounted_agent(agent_id, config) do
    assert {:ok, plugin_state} = Plugin.mount(%{id: agent_id}, config)
    %{id: agent_id, state: %{__memory__: plugin_state}}
  end
end
