defmodule Jido.Memory.Phase03IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.LongTermStoreContract
  alias Jido.Memory.LongTermStoreFixtures
  alias Jido.Memory.Plugin
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime

  setup_all do
    Code.require_file(Path.expand("../../examples/postgres_tiered_agent.exs", __DIR__))
    :ok
  end

  test "shared long-term store contract passes for ETS and Postgres" do
    for {name, backend} <- [
          {:ets, LongTermStoreFixtures.backend("phase03_contract_ets")},
          {:postgres, LongTermStoreFixtures.postgres_backend("phase03_contract_pg")}
        ] do
      target = LongTermStoreFixtures.target("phase03-contract-#{name}")
      namespace = LongTermStoreFixtures.namespace("phase03-contract-#{name}")

      assert {:ok, %{record: %Record{}, upserted: %Record{}, fetched: %Record{}, deleted?: true}} =
               LongTermStoreContract.exercise_core_flow(
                 backend,
                 target,
                 LongTermStoreFixtures.durable_attrs("phase03 durable #{name}"),
                 %{text_contains: "updated", classes: [:semantic], tags_any: ["durable"]},
                 namespace: namespace
               )
    end
  end

  test "ETS and Postgres return the same overlapping durable query subset and prune semantics" do
    query = %{classes: [:semantic], tags_any: ["important"], text_contains: "shared durable", order: :asc}

    results_by_backend =
      for {name, backend} <- [
            {:ets, LongTermStoreFixtures.backend("phase03_query_ets")},
            {:postgres, LongTermStoreFixtures.postgres_backend("phase03_query_pg")}
          ],
          into: %{} do
        target = LongTermStoreFixtures.target("phase03-query-#{name}")
        namespace = LongTermStoreFixtures.namespace("phase03-query-#{name}")
        runtime_opts = backend_runtime_opts(backend, namespace)
        {module, backend_opts} = backend

        assert {:ok, _meta} = module.init(backend_opts)

        remember!(backend, target, LongTermStoreFixtures.durable_attrs("shared durable alpha"), runtime_opts)
        remember!(backend, target, LongTermStoreFixtures.durable_attrs("shared durable beta"), runtime_opts)

        remember!(
          backend,
          target,
          LongTermStoreFixtures.durable_attrs("non matching note", %{tags: ["other"]}),
          runtime_opts
        )

        assert {:ok, records} = module.retrieve(target, query, runtime_opts)

        assert {:ok, %{pruned: 1, deleted?: true}} =
                 LongTermStoreContract.exercise_prune_flow(
                   backend,
                   target,
                   LongTermStoreFixtures.expired_attrs("expired #{name}", System.system_time(:millisecond)),
                   LongTermStoreFixtures.active_attrs("active #{name}", System.system_time(:millisecond)),
                   namespace: LongTermStoreFixtures.namespace("phase03-prune-#{name}")
                 )

        {name, Enum.map(records, & &1.text)}
      end

    assert Enum.sort(results_by_backend.ets) == Enum.sort(results_by_backend.postgres)
  end

  test "Tiered works over Postgres long-term storage and the operational example executes" do
    agent = mounted_agent("phase03-tiered-agent", ProviderFixtures.postgres_tiered_provider("phase03_tiered_pg"))

    assert {:ok, %Record{id: id}} =
             Runtime.remember(
               agent,
               ProviderFixtures.important_attrs("phase03 durable tiered memory", %{tier: :mid}),
               []
             )

    assert {:ok, %{promoted_to_long: 1}} = Runtime.consolidate(agent, tier: :mid)
    assert {:ok, %Record{id: ^id}} = Runtime.get(agent, id, tier: :long)

    assert {:ok, records} =
             Runtime.retrieve(agent, %{text_contains: "phase03 durable", tiers: [:short, :mid, :long]}, [])

    assert id in Enum.map(records, & &1.id)

    prefix = "docs_postgres_tiered_#{System.unique_integer([:positive])}"

    assert {:ok,
            %{
              record: %Record{},
              lifecycle_result: %{promoted_to_long: 1},
              long_record: %Record{},
              records: [%Record{} | _]
            }} = Example.PostgresTieredAgent.run_demo("docs-postgres-tiered-agent", prefix)
  end

  defp backend_runtime_opts({_module, opts}, namespace), do: Keyword.put(opts, :namespace, namespace)

  defp remember!({module, _opts}, target, attrs, runtime_opts) do
    assert {:ok, %Record{}} = module.remember(target, attrs, runtime_opts)
  end

  defp mounted_agent(agent_id, provider) do
    assert {:ok, plugin_state} = Plugin.mount(%{id: agent_id}, %{provider: provider})
    %{id: agent_id, state: %{__memory__: plugin_state}}
  end
end
