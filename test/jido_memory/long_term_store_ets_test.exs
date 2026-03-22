defmodule Jido.Memory.LongTermStoreETSTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.LongTermStore
  alias Jido.Memory.LongTermStore.ETS, as: LongTermETS
  alias Jido.Memory.LongTermStoreContract
  alias Jido.Memory.LongTermStoreFixtures
  alias Jido.Memory.Record

  test "ETS long-term backend satisfies the shared core contract" do
    backend = LongTermStoreFixtures.backend("long_term_ets_contract")
    target = LongTermStoreFixtures.target("long-term-ets-core")
    namespace = LongTermStoreFixtures.namespace("ets-core")

    assert {:ok,
            %{
              meta: %{backend: LongTermETS},
              record: %Record{id: id, metadata: original_metadata},
              upserted: %Record{id: id, text: "ETS durable record updated", metadata: updated_metadata},
              fetched: %Record{id: id, text: "ETS durable record updated"},
              records: [%Record{id: id}],
              deleted?: true
            }} =
             LongTermStoreContract.exercise_core_flow(
               backend,
               target,
               LongTermStoreFixtures.durable_attrs("ETS durable record"),
               %{text_contains: "updated", classes: [:semantic], tags_any: ["durable"]},
               namespace: namespace
             )

    assert get_in(original_metadata, [:tiered, :tier]) == :long
    assert get_in(updated_metadata, [:tiered, :tier]) == :long
    assert get_in(updated_metadata, [:contract, :updated]) == true
  end

  test "ETS long-term backend keeps prune and forget semantics stable" do
    backend = LongTermStoreFixtures.backend("long_term_ets_prune")
    target = LongTermStoreFixtures.target("long-term-ets-prune")
    namespace = LongTermStoreFixtures.namespace("ets-prune")
    now = System.system_time(:millisecond)

    assert {:ok,
            %{
              meta: %{backend: LongTermETS},
              expired: %Record{},
              active: %Record{},
              pruned: 1,
              deleted?: true
            }} =
             LongTermStoreContract.exercise_prune_flow(
               backend,
               target,
               LongTermStoreFixtures.expired_attrs("expired durable record", now),
               LongTermStoreFixtures.active_attrs("active durable record", now),
               namespace: namespace
             )
  end

  test "production-ready durable query subset is documented explicitly" do
    assert LongTermStore.production_ready_query_subset() ==
             [:classes, :kinds, :tags_any, :tags_all, :text_contains, :since, :until, :limit, :order]

    assert LongTermStoreContract.production_ready_query_subset() ==
             LongTermStore.production_ready_query_subset()
  end
end
