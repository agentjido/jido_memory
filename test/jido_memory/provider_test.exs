defmodule Jido.Memory.ProviderTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderRef
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store.ETS

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

  test "provider ref rejects modules missing required callbacks" do
    assert {:error, %Jido.Memory.Error.InvalidProvider{provider: MissingCallbacksProvider}} =
             ProviderRef.normalize(MissingCallbacksProvider)
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
end
