defmodule Jido.Memory.LongTermStorePostgresTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.LongTermStore.Postgres
  alias Jido.Memory.LongTermStoreContract
  alias Jido.Memory.LongTermStoreFixtures
  alias Jido.Memory.Record

  test "Postgres long-term backend satisfies the shared core contract" do
    backend = LongTermStoreFixtures.postgres_backend("long_term_pg_contract")
    target = LongTermStoreFixtures.target("long-term-pg-core")
    namespace = LongTermStoreFixtures.namespace("pg-core")

    assert {:ok,
            %{
              meta: %{backend: Postgres, adapter: :postgrex, query_mode: :namespace_scan, selected_over: :redis},
              record: %Record{id: id, metadata: original_metadata},
              upserted: %Record{id: id, text: "Postgres durable record updated", metadata: updated_metadata},
              fetched: %Record{id: id, text: "Postgres durable record updated"},
              records: [%Record{id: id}],
              deleted?: true
            }} =
             LongTermStoreContract.exercise_core_flow(
               backend,
               target,
               LongTermStoreFixtures.durable_attrs("Postgres durable record"),
               %{text_contains: "updated", classes: [:semantic], tags_any: ["durable"]},
               namespace: namespace
             )

    assert get_in(original_metadata, [:tiered, :tier]) == :long
    assert get_in(updated_metadata, [:tiered, :tier]) == :long
    assert get_in(updated_metadata, [:contract, :updated]) == true
  end

  test "Postgres long-term backend keeps prune semantics stable" do
    backend = LongTermStoreFixtures.postgres_backend("long_term_pg_prune")
    target = LongTermStoreFixtures.target("long-term-pg-prune")
    namespace = LongTermStoreFixtures.namespace("pg-prune")
    now = System.system_time(:millisecond)

    assert {:ok,
            %{
              meta: %{backend: Postgres},
              expired: %Record{},
              active: %Record{},
              pruned: 1,
              deleted?: true
            }} =
             LongTermStoreContract.exercise_prune_flow(
               backend,
               target,
               LongTermStoreFixtures.expired_attrs("expired postgres durable record", now),
               LongTermStoreFixtures.active_attrs("active postgres durable record", now),
               namespace: namespace
             )
  end

  test "Postgres backend validates durable configuration requirements" do
    assert {:error, :database_required} = Postgres.validate_config(table: "missing_connection")

    assert :ok =
             Postgres.validate_config(LongTermStoreFixtures.postgres_opts("long_term_pg_validate"))
  end
end
