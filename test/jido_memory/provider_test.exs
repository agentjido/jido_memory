defmodule Jido.Memory.ProviderTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.LongTermStore.ETS, as: LongTermETS
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderRef
  alias Jido.Memory.ProviderRegistry
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store.ETS
  alias Jido.Memory.Support.ExternalProvider

  setup do
    table = String.to_atom("jido_memory_provider_test_#{System.unique_integer([:positive])}")
    opts = [table: table]
    assert :ok = ETS.ensure_ready(opts)
    %{store: {ETS, opts}, opts: opts}
  end

  defmodule MissingCallbacksProvider do
    def validate_config(_opts), do: :ok
  end

  test "provider ref defaults to the Basic provider" do
    assert {:ok, %ProviderRef{module: Basic, opts: []}} = ProviderRef.normalize(nil)
  end

  test "provider ref accepts built-in :tiered alias" do
    assert {:ok, %ProviderRef{module: Tiered, opts: []}} = ProviderRef.normalize(:tiered)
  end

  test "provider registry merges built-in and external aliases" do
    assert {:ok, aliases} =
             ProviderRegistry.registered(external_demo: ExternalProvider)

    assert aliases.basic == Basic
    assert aliases.tiered == Tiered
    assert aliases.external_demo == ExternalProvider
  end

  test "provider ref accepts external aliases through registry helpers" do
    assert {:ok, %ProviderRef{module: ExternalProvider, opts: []}} =
             ProviderRef.normalize(:external_demo, external_demo: ExternalProvider)
  end

  test "provider ref accepts direct external modules and tuples without registration", %{store: store} do
    assert {:ok, %ProviderRef{module: ExternalProvider, opts: []}} =
             ProviderRef.normalize(ExternalProvider)

    assert {:ok, %ProviderRef{module: ExternalProvider, opts: provider_opts}} =
             ProviderRef.normalize({ExternalProvider, [store: store]})

    assert Keyword.get(provider_opts, :store) == store
  end

  test "provider ref rejects modules missing required callbacks" do
    assert {:error, %Jido.Memory.Error.InvalidProvider{provider: MissingCallbacksProvider}} =
             ProviderRef.normalize(MissingCallbacksProvider)
  end

  test "provider resolution precedence is runtime opts then attrs then plugin state then default", %{store: store} do
    plugin_state = %{provider: {ExternalProvider, [store: store]}}
    attrs = %{provider: Basic}

    assert {:ok, %ProviderRef{module: Tiered}} =
             ProviderRef.resolve(attrs, [provider: :tiered], plugin_state)

    assert {:ok, %ProviderRef{module: Basic}} =
             ProviderRef.resolve(attrs, [], plugin_state)

    assert {:ok, %ProviderRef{module: ExternalProvider}} =
             ProviderRef.resolve(%{}, [], plugin_state)

    assert {:ok, %ProviderRef{module: Basic}} =
             ProviderRef.resolve(%{}, [], %{})
  end

  test "provider resolution rejects invalid alias maps deterministically" do
    assert {:error, :invalid_provider_aliases} =
             ProviderRef.resolve(%{provider: :external_demo, provider_aliases: %{external_demo: "bad"}}, [], %{})
  end

  test "runtime rejects invalid provider alias maps at the compatibility boundary", %{store: store} do
    assert {:error, :invalid_provider_aliases} =
             Runtime.remember(
               %{id: "provider-alias-invalid"},
               %{class: :episodic, text: "x"},
               store: store,
               provider: :external_demo,
               provider_aliases: %{external_demo: "bad"}
             )
  end

  test "runtime rejects invalid provider opts deterministically", %{store: store} do
    assert {:error, :invalid_provider_opts} =
             Runtime.remember(
               %{id: "provider-opts-invalid"},
               %{class: :episodic, text: "x"},
               store: store,
               provider: ExternalProvider,
               provider_opts: :invalid
             )
  end

  test "basic provider exposes core capabilities and info", %{store: store} do
    assert {:ok, meta} = Basic.init(store: store)

    assert Basic.capabilities(meta).core == true
    assert Basic.capabilities(meta).retrieval.explainable == false

    assert {:ok, %{provider: Basic, defaults: %{store: ^store}}} = Basic.info(meta, :all)
  end

  test "runtime retrieve and recall stay aligned for the Basic provider", %{store: store} do
    target = %{id: "provider-agent"}
    provider = {Basic, [store: store]}
    params = %{class: :episodic, kind: :event, text: "provider core flow"}

    assert {:ok, %{record: %Record{id: id}, fetched: %Record{id: fetched_id}, deleted?: true}} =
             ProviderContract.exercise_core_flow(
               provider,
               target,
               params,
               %{text_contains: "provider core flow"}
             )

    assert fetched_id == id

    assert {:ok, %Record{id: parity_id}} =
             Runtime.remember(target, %{class: :episodic, kind: :event, text: "provider parity"}, provider: provider)

    assert {:ok, [%Record{id: ^parity_id}]} =
             Runtime.retrieve(target, %{text_contains: "provider parity"}, provider: provider)

    assert {:ok, [%Record{id: ^parity_id}]} =
             Runtime.recall(
               %{id: "provider-agent", state: %{__memory__: %{store: store}}},
               %{text_contains: "provider parity"}
             )
  end

  test "runtime capabilities and info are available for the effective provider", %{store: store} do
    target = %{id: "provider-info-agent"}

    assert {:ok, capabilities} = Runtime.capabilities(target, store: store)
    assert capabilities.core == true
    assert capabilities.retrieval.explainable == false

    assert {:ok, %{provider: Basic}} = Runtime.info(target, [:provider], store: store)
  end

  test "runtime advanced helpers return unsupported capability for Basic", %{store: store} do
    target = %{id: "provider-unsupported-agent"}

    assert {:error, {:unsupported_capability, :consolidate}} =
             Runtime.consolidate(target, store: store)

    assert {:error, {:unsupported_capability, :explain_retrieval}} =
             Runtime.explain_retrieval(target, %{text_contains: "x"}, store: store)
  end

  test "runtime invalid provider references fail before dispatch", %{store: store} do
    target = %{id: "provider-invalid-agent"}

    assert {:error, {:invalid_provider, MissingCallbacksProvider}} =
             Runtime.remember(target, %{class: :episodic, text: "x"}, store: store, provider: MissingCallbacksProvider)
  end

  test "tiered provider exposes lifecycle and tier capabilities" do
    unique = System.unique_integer([:positive])

    provider =
      {Tiered,
       [
         short_store: {ETS, [table: :"jido_memory_tiered_short_#{unique}"]},
         mid_store: {ETS, [table: :"jido_memory_tiered_mid_#{unique}"]},
         long_term_store: {LongTermETS, [store: {ETS, [table: :"jido_memory_tiered_long_#{unique}"]}]}
       ]}

    assert {:ok, meta} = ProviderContract.provider_meta(provider)

    capabilities = Tiered.capabilities(meta)
    assert capabilities.core == true
    assert capabilities.retrieval.tiers == true
    assert capabilities.retrieval.explainable == true
    assert capabilities.lifecycle.consolidate == true
    assert meta.explainability.payload_version == 1
  end

  test "tiered explain_retrieval returns tier-aware explanation details" do
    unique = System.unique_integer([:positive])
    target = %{id: "tiered-explain-agent-#{unique}"}

    provider =
      {Tiered,
       [
         short_store: {ETS, [table: :"jido_memory_tiered_explain_short_#{unique}"]},
         mid_store: {ETS, [table: :"jido_memory_tiered_explain_mid_#{unique}"]},
         long_term_store: {LongTermETS, [store: {ETS, [table: :"jido_memory_tiered_explain_long_#{unique}"]}]}
       ]}

    assert {:ok, %Record{id: short_id}} =
             Runtime.remember(
               target,
               %{class: :episodic, kind: :event, text: "tiered explain short result"},
               provider: provider,
               tier: :short
             )

    assert {:ok, %Record{id: mid_id}} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "tiered explain mid result", importance: 1.0},
               provider: provider,
               tier: :mid
             )

    assert {:ok, explanation} =
             Runtime.explain_retrieval(
               target,
               %{text_contains: "tiered explain", tiers: [:short, :mid, :long], order: :asc},
               provider: provider
             )

    assert explanation.provider == Tiered
    assert explanation.requested_tiers == [:short, :mid, :long]
    assert MapSet.new(explanation.participating_tiers) == MapSet.new([:short, :mid])
    assert explanation.result_count == 2

    ids = Enum.map(explanation.results, & &1.id)
    assert short_id in ids
    assert mid_id in ids

    assert Enum.all?(explanation.results, fn result ->
             result.tier in [:short, :mid] and
               is_integer(result.rank) and
               :text_contains in result.matched_on
           end)

    assert explanation.extensions.tiered.counts_by_tier.short == 1
    assert explanation.extensions.tiered.counts_by_tier.mid == 1
    assert explanation.extensions.tiered.counts_by_tier.long == 0
    assert explanation.extensions.tiered.ranking.primary == :observed_at
  end

  test "tiered provider supports the canonical core flow" do
    unique = System.unique_integer([:positive])
    target = %{id: "tiered-core-agent-#{unique}"}

    provider =
      {Tiered,
       [
         short_store: {ETS, [table: :"jido_memory_tiered_core_short_#{unique}"]},
         mid_store: {ETS, [table: :"jido_memory_tiered_core_mid_#{unique}"]},
         long_term_store: {LongTermETS, [store: {ETS, [table: :"jido_memory_tiered_core_long_#{unique}"]}]}
       ]}

    assert {:ok, %{record: %Record{id: id}, fetched: %Record{id: fetched_id}, deleted?: true}} =
             ProviderContract.exercise_core_flow(
               provider,
               target,
               %{class: :episodic, kind: :event, text: "tiered provider core flow", importance: 1.0},
               %{text_contains: "tiered provider core flow"}
             )

    assert fetched_id == id
  end

  test "tiered consolidate promotes records across tiers" do
    unique = System.unique_integer([:positive])
    target = %{id: "tiered-promote-agent-#{unique}"}

    provider =
      {Tiered,
       [
         short_store: {ETS, [table: :"jido_memory_tiered_promote_short_#{unique}"]},
         mid_store: {ETS, [table: :"jido_memory_tiered_promote_mid_#{unique}"]},
         long_term_store: {LongTermETS, [store: {ETS, [table: :"jido_memory_tiered_promote_long_#{unique}"]}]}
       ]}

    assert {:ok, %Record{id: id}} =
             Runtime.remember(
               target,
               %{
                 class: :semantic,
                 kind: :fact,
                 text: "important durable memory promoted across tiers",
                 tags: ["important"],
                 importance: 1.0
               },
               provider: provider
             )

    assert {:ok, %{promoted_to_mid: 1}} = Runtime.consolidate(target, provider: provider, tier: :short)
    assert {:error, :not_found} = Runtime.get(target, id, provider: provider, tier: :short)
    assert {:ok, %Record{id: ^id}} = Runtime.get(target, id, provider: provider, tier: :mid)

    assert {:ok, %{promoted_to_long: 1}} = Runtime.consolidate(target, provider: provider, tier: :mid)
    assert {:error, :not_found} = Runtime.get(target, id, provider: provider, tier: :mid)
    assert {:ok, %Record{id: ^id}} = Runtime.get(target, id, provider: provider, tier: :long)
  end

  test "tiered provider rejects invalid lifecycle thresholds" do
    assert {:error, :invalid_lifecycle_threshold} =
             ProviderRef.normalize({Tiered, [lifecycle: [short_to_mid_threshold: 2.0]]})
  end
end
