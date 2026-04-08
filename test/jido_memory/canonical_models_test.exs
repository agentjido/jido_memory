defmodule Jido.Memory.CanonicalModelsTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.{
    CapabilitySet,
    Explanation,
    Hit,
    IngestRequest,
    IngestResult,
    ProviderInfo,
    Query,
    Record,
    RetrieveResult,
    Scope,
    Store
  }

  defmodule StubStore do
    @behaviour Store

    def ensure_ready(_opts), do: :ok
    def put(record, _opts), do: {:ok, record}

    def get({"agent:test", "found"}, _opts) do
      {:ok,
       Record.new!(%{
         id: "found",
         namespace: "agent:test",
         class: :semantic,
         kind: :fact,
         text: "found",
         observed_at: 1
       })}
    end

    def get({"agent:test", "missing"}, _opts), do: :not_found
    def get(_key, _opts), do: {:error, :boom}
    def delete(_key, _opts), do: :ok
    def query(_query, _opts), do: {:ok, []}
    def prune_expired(_opts), do: {:ok, 0}
  end

  test "Hit normalizes record attrs and trims match reasons" do
    assert {:ok, %Hit{} = hit} =
             Hit.new(%{
               record: record_attrs(),
               score: 0.91,
               rank: 1,
               matched_on: [" text ", "", "tag "],
               metadata: %{source: "unit"},
               extensions: %{provider_score: 91}
             })

    assert %Record{text: "stored fact"} = hit.record
    assert hit.score == 0.91
    assert hit.rank == 1
    assert hit.matched_on == ["text", "tag"]
    assert hit.metadata.source == "unit"
    assert hit.extensions.provider_score == 91
  end

  test "Hit validates invalid rank and score values" do
    assert {:error, {:invalid_hit_rank, 0}} = Hit.new(%{record: record_attrs(), rank: 0})
    assert {:error, {:invalid_hit_score, "high"}} = Hit.new(%{record: record_attrs(), score: "high"})
    assert_raise ArgumentError, ~r/invalid memory hit/, fn -> Hit.new!(%{record: record_attrs(), rank: 0}) end
  end

  test "RetrieveResult builds from records and hit attrs" do
    record = Record.new!(record_attrs(%{text: "alpha"}))
    record_id = record.id

    from_records =
      RetrieveResult.from_records([record],
        query: Query.new!(%{namespace: "agent:test", text_contains: "alpha"}),
        scope: %{namespace: "agent:test", provider: Jido.Memory.Provider.Basic},
        provider: %{provider: Jido.Memory.Provider.Basic, capabilities: [:retrieve]},
        total_count: 1
      )

    assert [%Record{id: ^record_id}] = RetrieveResult.records(from_records)
    assert from_records.total_count == 1
    assert %Scope{namespace: "agent:test"} = from_records.scope
    assert %ProviderInfo{provider: Jido.Memory.Provider.Basic} = from_records.provider

    assert {:ok, %RetrieveResult{hits: [%Hit{rank: 2, matched_on: ["text"]}]}} =
             RetrieveResult.new(%{
               hits: [
                 %{
                   record: record_attrs(%{text: "beta"}),
                   rank: 2,
                   matched_on: [" text "]
                 }
               ],
               total_count: 1
             })
  end

  test "RetrieveResult validates invalid total count" do
    assert {:error, {:invalid_total_count, -1}} = RetrieveResult.new(%{hits: [], total_count: -1})
  end

  test "IngestRequest normalizes record maps and scope maps" do
    assert {:ok, %IngestRequest{} = request} =
             IngestRequest.new(%{
               records: [record_attrs(%{text: "first"}), record_attrs(%{text: "second"})],
               scope: %{namespace: "agent:test", provider: Jido.Memory.Provider.Basic},
               metadata: %{batch: true},
               extensions: %{source: :import}
             })

    assert length(request.records) == 2
    assert %Scope{namespace: "agent:test"} = request.scope
    assert request.metadata.batch == true
    assert request.extensions.source == :import
  end

  test "IngestRequest rejects invalid records" do
    assert {:error, {:invalid_ingest_record, 123}} = IngestRequest.new(%{records: [123]})

    assert_raise ArgumentError, ~r/invalid ingest request/, fn ->
      IngestRequest.new!(%{records: [123]})
    end
  end

  test "IngestResult defaults accepted count and normalizes provider and scope" do
    assert {:ok, %IngestResult{} = result} =
             IngestResult.new(%{
               records: [record_attrs(%{text: "stored"})],
               rejected: [%{id: "bad-1", reason: :duplicate}],
               scope: %{namespace: "agent:test", provider: Jido.Memory.Provider.Basic},
               provider: %{
                 provider: Jido.Memory.Provider.Basic,
                 capabilities: [:ingest],
                 metadata: %{store: :ets}
               },
               metadata: %{import_id: "batch-1"}
             })

    assert result.accepted_count == 1
    assert [%Record{text: "stored"}] = result.records
    assert %Scope{namespace: "agent:test"} = result.scope
    assert %ProviderInfo{metadata: %{store: :ets}} = result.provider
    assert [%{reason: :duplicate}] = result.rejected
  end

  test "IngestResult validates rejected shape" do
    assert {:error, {:invalid_rejected, :bad}} = IngestResult.new(%{rejected: :bad})

    assert_raise ArgumentError, ~r/invalid ingest result/, fn ->
      IngestResult.new!(%{accepted_count: -1})
    end
  end

  test "Explanation normalizes nested query scope and provider values" do
    assert {:ok, %Explanation{} = explanation} =
             Explanation.new(%{
               query: %{namespace: "agent:test", text_contains: "beam"},
               scope: %{namespace: "agent:test", provider: Jido.Memory.Provider.Basic},
               provider: %{provider: Jido.Memory.Provider.Basic, capabilities: [:retrieve]},
               summary: " matched on text ",
               reasons: [%{id: "mem-1", matched_on: ["text"]}],
               metadata: %{strategy: "substring"},
               extensions: %{provider_latency_ms: 2}
             })

    assert %Query{text_contains: "beam"} = explanation.query
    assert %Scope{namespace: "agent:test"} = explanation.scope
    assert %ProviderInfo{provider: Jido.Memory.Provider.Basic} = explanation.provider
    assert explanation.summary == "matched on text"
    assert explanation.metadata.strategy == "substring"
    assert explanation.extensions.provider_latency_ms == 2
  end

  test "Explanation validates invalid reasons and summary inputs" do
    assert {:error, {:invalid_reasons, :bad}} = Explanation.new(%{reasons: :bad})
    assert {:error, {:invalid_summary, 123}} = Explanation.new(%{summary: 123})

    assert {:ok, %Explanation{summary: nil}} = Explanation.new(%{summary: "   "})
  end

  test "CapabilitySet, Scope, and ProviderInfo normalize shared metadata" do
    assert {:ok, %CapabilitySet{} = capability_set} =
             CapabilitySet.new(%{
               key: :basic,
               provider: Jido.Memory.Provider.Basic,
               capabilities: [:retrieve, :ingest, :retrieve],
               descriptor: %{
                 retrieval: %{explainable: true},
                 ingestion: %{batch: true, access: :runtime}
               },
               metadata: %{mode: "unit"}
             })

    assert capability_set.capabilities == [:retrieve, :ingest]
    assert capability_set.key == :basic
    assert CapabilitySet.supports?(capability_set, :ingest)
    assert CapabilitySet.supports?(capability_set, [:retrieval, :explainable])
    assert CapabilitySet.get(capability_set, [:ingestion, :access]) == :runtime
    refute CapabilitySet.supports?(capability_set, :forget)

    assert {:ok, %Scope{} = scope} =
             Scope.new(%{
               namespace: " agent:test ",
               provider: Jido.Memory.Provider.Basic,
               metadata: %{channel: "test"}
             })

    assert scope.namespace == "agent:test"
    assert scope.provider_key == :basic
    assert scope.provider_name == "basic"
    assert Scope.provider_name(Jido.Memory.Provider.Basic) == "basic"

    info =
      ProviderInfo.from_capabilities(
        Jido.Memory.Provider.Basic,
        capability_set,
        scope: scope,
        version: "1.0.0",
        description: "Basic provider"
      )

    assert info.name == "basic"
    assert info.key == :basic
    assert info.scope == scope
    assert info.version == "1.0.0"
    assert info.description == "Basic provider"
    assert info.capabilities == [:retrieve, :ingest]
    assert info.capability_descriptor.retrieval.explainable == true
  end

  test "CapabilitySet, Scope, and ProviderInfo validate invalid inputs" do
    assert {:error, {:invalid_capability, "retrieve"}} = CapabilitySet.new(%{capabilities: ["retrieve"]})
    assert {:error, {:invalid_scope_metadata, :bad}} = Scope.new(%{metadata: :bad})

    assert {:error, {:invalid_provider_name, "   "}} =
             ProviderInfo.new(%{provider: Jido.Memory.Provider.Basic, name: "   "})
  end

  test "Store normalizes declarations and fetch semantics" do
    assert {:ok, {StubStore, []}} = Store.normalize_store(StubStore)
    assert {:ok, {StubStore, [table: :memory]}} = Store.normalize_store({StubStore, [table: :memory]})
    assert {:error, :missing_store} = Store.normalize_store(nil)
    assert {:error, {:invalid_store, 123}} = Store.normalize_store(123)

    assert {:ok, %Record{id: "found"}} = Store.fetch(StubStore, {"agent:test", "found"}, [])
    assert {:error, :not_found} = Store.fetch(StubStore, {"agent:test", "missing"}, [])
    assert {:error, :boom} = Store.fetch(StubStore, {"agent:test", "other"}, [])
  end

  defp record_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        namespace: "agent:test",
        class: :semantic,
        kind: :fact,
        text: "stored fact",
        observed_at: 1_700_000_000_000,
        metadata: %{source: "test"}
      },
      overrides
    )
  end
end
