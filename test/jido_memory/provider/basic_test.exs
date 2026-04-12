defmodule Jido.Memory.Provider.BasicTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.{Explanation, IngestRequest, ProviderInfo, Query, Record, RetrieveResult, Runtime}
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Store.{ETS, Redis}

  setup do
    table = String.to_atom("jido_memory_provider_basic_test_#{System.unique_integer([:positive])}")
    store = {ETS, [table: table]}
    assert :ok = ETS.ensure_ready(table: table)
    %{table: table, store: store, opts: [store: store, namespace: "agent:basic"]}
  end

  test "validate_config child_specs capabilities and info", %{store: store} do
    assert :ok = Basic.validate_config(namespace: "agent:test", store: store, store_opts: [])
    assert {:error, :invalid_namespace} = Basic.validate_config(namespace: 123, store: store)
    assert {:error, :invalid_store} = Basic.validate_config(namespace: "agent:test", store: "bad_store")

    assert {:error, {:store_not_loaded, MissingStore, _reason}} =
             Basic.validate_config(namespace: "agent:test", store: MissingStore)

    assert {:error, :invalid_store_opts} =
             Basic.validate_config(namespace: "agent:test", store: store, store_opts: :bad)

    assert {:error, :missing_command_fn} =
             Basic.validate_config(namespace: "agent:test", store: Redis, store_opts: [])

    assert {:error, :invalid_provider_opts} = Basic.validate_config(:bad)
    assert [] == Basic.child_specs([])

    assert {:ok, capability_set} = Basic.capabilities(store: store, namespace: "agent:test")
    assert :retrieve in capability_set.capabilities

    assert {:ok, %ProviderInfo{name: "basic"} = info} =
             Basic.info([store: store, namespace: "agent:test"], :all)

    assert info.metadata.store == store
  end

  test "remember get retrieve and forget support target and plugin-state resolution", %{store: store} do
    agent = %{id: "basic-agent"}
    plugin_agent = %{id: "ignored", state: %{__memory__: %{namespace: "agent:plugin-basic", store: store}}}

    assert {:ok, %Record{id: id, namespace: "agent:basic-agent"}} =
             Basic.remember(agent, %{class: :semantic, kind: :fact, text: "remember me"}, store: store)

    assert {:ok, %Record{id: ^id}} = Basic.get(agent, id, store: store)

    query = Query.new!(%{text_contains: "remember"})

    assert {:ok, %RetrieveResult{hits: [%{record: %Record{id: ^id}}]}} =
             Basic.retrieve(agent, query, store: store)

    assert {:ok, %Record{namespace: "agent:plugin-basic"}} =
             Basic.remember(plugin_agent, %{class: :semantic, kind: :fact, text: "plugin path"}, [])

    assert {:ok, true} = Basic.forget(agent, id, store: store)
    assert {:ok, false} = Basic.forget(agent, id, store: store)
    assert {:error, :not_found} = Basic.get(agent, id, store: store)
  end

  test "retrieve validates invalid inputs and prune supports invalid opts", %{store: store} do
    assert {:error, :invalid_query} = Basic.retrieve(%{}, :bad, store: store)
    assert {:error, :invalid_attrs} = Basic.remember(%{}, :bad, store: store)
    assert {:error, :invalid_id} = Basic.get(%{}, 123, store: store)
    assert {:error, :invalid_id} = Basic.forget(%{}, 123, store: store)
    assert {:error, :invalid_opts} = Basic.prune(%{}, :bad)
  end

  test "ingest explain and consolidate cover canonical lifecycle paths", %{store: store} do
    expired_time = System.system_time(:millisecond) - 1_000

    assert {:ok, %Record{}} =
             Basic.remember(
               %{id: "basic-ingest"},
               %{
                 class: :episodic,
                 kind: :event,
                 text: "expired",
                 expires_at: expired_time
               },
               store: store
             )

    request =
      IngestRequest.new!(%{
        records: [
          %{class: :semantic, kind: :fact, text: "scope injected"}
        ],
        scope: %{namespace: "agent:ingested"}
      })

    assert {:ok, ingest_result} = Basic.ingest(%{}, request, store: store)
    assert [%Record{namespace: "agent:ingested"}] = ingest_result.records

    assert {:ok, %Explanation{summary: summary, reasons: reasons}} =
             Basic.explain_retrieval(
               %{id: "basic-explain"},
               %{namespace: "agent:ingested", text_contains: "scope"},
               store: store
             )

    assert summary =~ "hit"
    assert is_list(reasons)

    assert {:ok, %{pruned_count: pruned_count, status: :ok}} =
             Basic.consolidate(%{id: "basic-ingest"}, store: store)

    assert pruned_count >= 1
  end

  test "ingest rejects invalid requests and records", %{store: store} do
    assert {:error, :invalid_ingest_request} = Basic.ingest(%{}, :bad, store: store)

    assert {:error, {:invalid_ingest_record, 123}} =
             Basic.ingest(%{}, %{records: [123]}, store: store, namespace: "agent:bad")
  end

  test "provider integrates with runtime via direct module provider", %{store: store} do
    assert {:ok, %Record{namespace: "agent:runtime-basic"}} =
             Runtime.remember(
               %{id: "runtime-basic"},
               %{class: :semantic, kind: :fact, text: "runtime basic"},
               provider: Basic,
               provider_opts: [store: store]
             )
  end
end
