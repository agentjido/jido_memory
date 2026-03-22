defmodule Jido.Memory.ProviderTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.LongTermStore.ETS, as: LongTermETS
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Provider.Mem0
  alias Jido.Memory.Provider.Mirix
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderFixtures
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

  test "provider ref accepts built-in :mem0 alias" do
    assert {:ok, %ProviderRef{module: Mem0, opts: []}} = ProviderRef.normalize(:mem0)
  end

  test "provider registry reserves the built-in :mirix alias" do
    assert {:ok, Jido.Memory.Provider.Mirix} = ProviderRegistry.resolve_alias(:mirix)
  end

  test "provider registry reserves the built-in :mem0 alias" do
    assert {:ok, Jido.Memory.Provider.Mem0} = ProviderRegistry.resolve_alias(:mem0)
  end

  test "provider registry merges built-in and external aliases" do
    assert {:ok, aliases} =
             ProviderRegistry.registered(external_demo: ExternalProvider)

    assert aliases.basic == Basic
    assert aliases.mem0 == Mem0
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
    assert Basic.capabilities(meta).ingestion.batch == false
    assert Basic.capabilities(meta).governance.protected_memory == false

    assert {:ok, %{provider: Basic, defaults: %{store: ^store}}} = Basic.info(meta, :all)
  end

  test "mem0 provider exposes baseline topology and capability metadata", %{store: store} do
    assert {:ok, meta} =
             Mem0.init(
               store: store,
               namespace: "agent:mem0-baseline",
               scoped_identity: [user: "cfg-user", app: "cfg-app"]
             )

    capabilities = Mem0.capabilities(meta)
    assert capabilities.core == true
    assert capabilities.retrieval.explainable == false
    assert capabilities.retrieval.provider_extensions == true
    assert capabilities.retrieval.scoped == true
    assert capabilities.retrieval.graph_augmentation == false
    assert capabilities.ingestion.access == :provider_direct
    assert capabilities.operations.feedback == :provider_direct
    assert capabilities.operations.export == :provider_direct
    assert capabilities.operations.history == :provider_direct

    assert {:ok, info} = Mem0.info(meta, [:provider, :provider_style, :topology, :scoped_identity])
    assert info.provider == Mem0
    assert info.provider_style == :mem0
    assert info.topology.archetype == :extraction_reconciliation
    assert info.topology.retrieval.scoped == true
    assert info.scoped_identity.enabled == true
    assert info.scoped_identity.defaults.user_id == "cfg-user"
    assert info.scoped_identity.defaults.app_id == "cfg-app"
    assert info.scoped_identity.supported_dimensions == [:user, :agent, :app, :run]
  end

  test "mem0 provider resolves scope ids from runtime opts then target data then provider config", %{store: store} do
    target = %{id: "target-agent", app_id: "target-app", run_id: "target-run"}

    provider =
      {Mem0,
       [
         store: store,
         namespace: "agent:mem0-scope",
         scoped_identity: [user: "cfg-user", app: "cfg-app", run: "cfg-run"]
       ]}

    assert {:ok, %Record{} = record} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "scope precedence"},
               provider: provider,
               user_id: "runtime-user",
               agent_id: "runtime-agent"
             )

    assert get_in(record.metadata, ["mem0", "scope"]) == %{
             "user_id" => "runtime-user",
             "agent_id" => "runtime-agent",
             "app_id" => "target-app",
             "run_id" => "target-run"
           }
  end

  test "mem0 canonical reads stay within the effective scope", %{store: store} do
    target = %{id: "scope-target-agent"}

    provider =
      {Mem0,
       [
         store: store,
         namespace: "agent:mem0-scope-reads"
       ]}

    assert {:ok, %Record{id: user_1_id}} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "user one memory"},
               provider: provider,
               user_id: "user-1"
             )

    assert {:ok, %Record{id: user_2_id}} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "user two memory"},
               provider: provider,
               user_id: "user-2"
             )

    assert {:ok, [%Record{id: ^user_1_id}]} =
             Runtime.retrieve(target, %{text_contains: "user"}, provider: provider, user_id: "user-1")

    assert {:error, :not_found} =
             Runtime.get(target, user_2_id, provider: provider, user_id: "user-1")

    assert {:ok, false} =
             Runtime.forget(target, user_2_id, provider: provider, user_id: "user-1")

    assert {:ok, %Record{id: ^user_2_id}} =
             Runtime.get(target, user_2_id, provider: provider, user_id: "user-2")
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
    assert capabilities.retrieval.provider_extensions == true
    assert capabilities.lifecycle.consolidate == true
    assert capabilities.lifecycle.inspect == true
    assert capabilities.ingestion.batch == false
    assert capabilities.governance.protected_memory == false
    assert meta.explainability.payload_version == 1
    assert meta.lifecycle_inspection.access == :provider_direct
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

    assert ProviderContract.canonical_explanation?(explanation)
    assert explanation.provider == Tiered
    assert explanation.result_count == 2

    ids = Enum.map(explanation.results, & &1.id)
    assert short_id in ids
    assert mid_id in ids

    assert Enum.all?(explanation.results, fn result ->
             result.tier in [:short, :mid] and
               is_integer(result.rank) and
               :text_contains in result.matched_on
           end)

    assert explanation.extensions.tiered.requested_tiers == [:short, :mid, :long]
    assert MapSet.new(explanation.extensions.tiered.participating_tiers) == MapSet.new([:short, :mid])
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

  test "tiered lifecycle inspection summarizes promoted and skipped outcomes" do
    unique = System.unique_integer([:positive])
    now = 1_234_567_890
    target = %{id: "tiered-lifecycle-agent-#{unique}"}

    provider =
      {Tiered,
       [
         short_store: {ETS, [table: :"jido_memory_tiered_lifecycle_short_#{unique}"]},
         mid_store: {ETS, [table: :"jido_memory_tiered_lifecycle_mid_#{unique}"]},
         long_term_store: {LongTermETS, [store: {ETS, [table: :"jido_memory_tiered_lifecycle_long_#{unique}"]}]}
       ]}

    assert {:ok, %Record{id: promoted_id}} =
             Runtime.remember(
               target,
               %{
                 class: :semantic,
                 kind: :fact,
                 text: "important durable tiered lifecycle record",
                 tags: ["important"],
                 importance: 1.0
               },
               provider: provider,
               tier: :short
             )

    assert {:ok, %Record{id: skipped_id}} =
             Runtime.remember(
               target,
               %{
                 class: :working,
                 kind: :event,
                 text: "short lived scratch note",
                 importance: 0.1
               },
               provider: provider,
               tier: :short
             )

    assert {:ok, lifecycle_result} =
             Runtime.consolidate(target, provider: provider, tier: :short, now: now)

    assert lifecycle_result.promoted_to_mid == 1
    assert lifecycle_result.tier_results.short.source_tier == :short
    assert lifecycle_result.tier_results.short.destination_tier == :mid
    assert lifecycle_result.tier_results.short.threshold == 0.65
    assert lifecycle_result.tier_results.short.promoted == 1
    assert lifecycle_result.tier_results.short.skipped == 1

    decisions = Map.new(lifecycle_result.tier_results.short.decisions, &{&1.id, &1})

    assert decisions[promoted_id].decision == :promoted
    assert decisions[promoted_id].source_tier == :short
    assert decisions[promoted_id].destination_tier == :mid
    assert decisions[promoted_id].reason == nil

    assert decisions[skipped_id].decision == :skipped
    assert decisions[skipped_id].source_tier == :short
    assert decisions[skipped_id].destination_tier == :mid
    assert decisions[skipped_id].reason == :below_threshold

    assert {:ok, inspection} = Tiered.inspect_lifecycle(target, provider: provider, tiers: [:short, :mid, :long])

    assert inspection.provider == Tiered
    assert inspection.current_tiers.short == 1
    assert inspection.current_tiers.mid == 1
    assert inspection.current_tiers.long == 0
    assert inspection.totals.promoted == 1
    assert inspection.totals.skipped == 1
    assert inspection.recent_outcomes.short.destination_tier == :mid
    assert inspection.recent_outcomes.short.promoted == 1
    assert inspection.recent_outcomes.short.skipped == 1
    assert inspection.recent_outcomes.short.skipped_reasons.below_threshold == 1

    records = Map.new(inspection.records, &{&1.id, &1})

    assert records[promoted_id].tier == :mid
    assert records[promoted_id].decision == :promoted
    assert records[promoted_id].source_tier == :short
    assert records[promoted_id].destination_tier == :mid
    assert records[promoted_id].promotion_count == 1
    assert records[promoted_id].last_evaluated_at == now

    assert records[skipped_id].tier == :short
    assert records[skipped_id].decision == :skipped
    assert records[skipped_id].source_tier == :short
    assert records[skipped_id].destination_tier == :mid
    assert records[skipped_id].skip_reason == :below_threshold
    assert records[skipped_id].last_evaluated_at == now

    assert {:ok, %Record{metadata: metadata}} =
             Runtime.get(target, skipped_id, provider: provider, tier: :short)

    assert get_in(metadata, [:tiered, :lifecycle, :last_decision]) == :skipped
    assert get_in(metadata, [:tiered, :lifecycle, :last_skip_reason]) == :below_threshold
  end

  test "tiered provider rejects invalid lifecycle thresholds" do
    assert {:error, :invalid_lifecycle_threshold} =
             ProviderRef.normalize({Tiered, [lifecycle: [short_to_mid_threshold: 2.0]]})
  end

  test "mirix provider exposes manager topology and built-in capability metadata" do
    provider = ProviderFixtures.mirix_provider("provider_mirix_meta")

    assert {:ok, meta} = ProviderContract.provider_meta(provider)

    assert meta.provider == Mirix
    assert meta.explainability.payload_version == 1
    assert meta.explainability.extensions == [:mirix]

    assert Enum.map(meta.managers, & &1.memory_type) == [:core, :episodic, :semantic, :procedural, :resource, :vault]
    assert Enum.any?(meta.managers, &(&1.memory_type == :vault and &1.public? == false))

    capabilities = Mirix.capabilities(meta)
    assert capabilities.core == true
    assert capabilities.retrieval.explainable == true
    assert capabilities.retrieval.active == true
    assert capabilities.retrieval.memory_types == true
    assert capabilities.ingestion.batch == true
    assert capabilities.ingestion.multimodal == true
    assert capabilities.ingestion.routed == true
    assert capabilities.governance.protected_memory == true
    assert capabilities.governance.exact_preservation == true
    assert capabilities.governance.access == :provider_direct

    assert {:ok, %{provider: Mirix, managers: managers, defaults: %{stores: stores}}} =
             Mirix.info(meta, [:provider, :managers, :defaults])

    assert length(managers) == 6

    assert MapSet.new(Map.keys(stores)) ==
             MapSet.new([:core, :episodic, :procedural, :resource, :semantic, :vault])
  end

  test "mirix provider supports the canonical core flow and alias equivalence" do
    provider = ProviderFixtures.mirix_provider("provider_mirix_core")
    {:mirix, provider_opts} = provider
    target = %{id: "mirix-core-agent-#{System.unique_integer([:positive])}"}

    assert {:ok, %{module: Mirix, opts: normalized_opts}} = ProviderRef.normalize(provider)
    assert {:ok, %{module: Mirix, opts: ^normalized_opts}} = ProviderRef.normalize({Mirix, provider_opts})

    assert {:ok, %{record: %Record{id: id}, fetched: %Record{id: fetched_id}, deleted?: true}} =
             ProviderContract.exercise_core_flow(
               provider,
               target,
               %{class: :semantic, kind: :fact, text: "mirix provider core flow"},
               %{text_contains: "mirix provider core flow", classes: [:semantic]}
             )

    assert fetched_id == id
  end
end
