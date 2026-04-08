defmodule Jido.Memory.CanonicalEdgeCasesTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.{
    CapabilitySet,
    Hit,
    IngestRequest,
    IngestResult,
    ProviderInfo,
    Record,
    RetrieveResult,
    Scope
  }

  alias Jido.Memory.Provider.Basic

  test "CapabilitySet validates provider metadata and raises on invalid values" do
    assert {:error, {:invalid_provider, "basic"}} = CapabilitySet.new(%{provider: "basic"})
    assert {:error, {:invalid_capabilities, :bad}} = CapabilitySet.new(%{capabilities: :bad})
    assert {:error, {:invalid_capability_metadata, :bad}} = CapabilitySet.new(%{metadata: :bad})
    assert {:error, :invalid_capability_set} = CapabilitySet.new(:bad)

    assert_raise ArgumentError, ~r/invalid capability set/, fn ->
      CapabilitySet.new!(%{capabilities: ["retrieve"]})
    end
  end

  test "ProviderInfo defaults provider names and validates invalid branches" do
    assert {:ok, %ProviderInfo{name: "basic", provider: Basic, version: nil, description: nil}} =
             ProviderInfo.new(%{provider: Basic})

    assert {:error, {:invalid_provider, "basic"}} =
             ProviderInfo.new(%{name: "basic", provider: "basic"})

    assert {:error, {:invalid_provider_string, 123}} =
             ProviderInfo.new(%{name: "basic", provider: Basic, version: 123})

    assert {:error, {:invalid_scope, :bad}} =
             ProviderInfo.new(%{name: "basic", provider: Basic, scope: :bad})

    assert {:error, {:invalid_provider_metadata, :bad}} =
             ProviderInfo.new(%{name: "basic", provider: Basic, metadata: :bad})

    assert {:error, :invalid_provider_info} = ProviderInfo.new(:bad)

    assert_raise ArgumentError, ~r/invalid provider info/, fn ->
      ProviderInfo.new!(%{provider: Basic, name: "   "})
    end
  end

  test "Scope validates explicit provider names and invalid inputs" do
    assert {:ok, %Scope{provider_name: "custom"}} =
             Scope.new(%{provider: Basic, provider_name: " custom "})

    assert {:error, {:invalid_provider, "basic"}} = Scope.new(%{provider: "basic"})
    assert {:error, {:invalid_provider_name, 123}} = Scope.new(%{provider_name: 123})
    assert {:error, {:invalid_scope_value, 123}} = Scope.new(%{namespace: 123})
    assert {:error, :invalid_scope} = Scope.new(:bad)

    assert_raise ArgumentError, ~r/invalid memory scope/, fn ->
      Scope.new!(%{provider_name: 123})
    end
  end

  test "Hit supports alias inputs and validates error branches" do
    assert {:ok, %Hit{record: %Record{text: "alias path"}}} =
             Hit.new(%{memory: record_attrs(%{text: "alias path"})})

    hit =
      Hit.from_record(
        Record.new!(record_attrs(%{id: "from-record"})),
        score: 0.5,
        rank: 2,
        matched_on: ["text"],
        metadata: %{via: :from_record},
        extensions: %{raw: true}
      )

    assert hit.rank == 2
    assert hit.metadata.via == :from_record
    assert hit.extensions.raw == true

    assert {:error, {:invalid_hit_record, :bad}} = Hit.new(%{record: :bad})
    assert {:error, {:invalid_match_reason, 123}} = Hit.new(%{record: record_attrs(), matched_on: [123]})
    assert {:error, {:invalid_matched_on, :bad}} = Hit.new(%{record: record_attrs(), matched_on: :bad})
    assert {:error, {:invalid_hit_metadata, :bad}} = Hit.new(%{record: record_attrs(), metadata: :bad})
    assert {:error, {:invalid_hit_extensions, :bad}} = Hit.new(%{record: record_attrs(), extensions: :bad})
    assert {:error, :invalid_hit} = Hit.new(:bad)
  end

  test "RetrieveResult validates alias inputs and error branches" do
    record = Record.new!(record_attrs(%{id: "result-record"}))

    assert {:ok, %RetrieveResult{hits: [%Hit{rank: 1, record: %Record{id: "result-record"}}]}} =
             RetrieveResult.new(%{
               records: [record],
               query: %{namespace: "agent:test"},
               metadata: nil,
               extensions: nil
             })

    assert {:error, {:invalid_hits, :bad}} = RetrieveResult.new(%{hits: :bad})
    assert {:error, {:invalid_query, :bad}} = RetrieveResult.new(%{hits: [], query: :bad})
    assert {:error, {:invalid_scope, :bad}} = RetrieveResult.new(%{hits: [], scope: :bad})
    assert {:error, {:invalid_provider_info, :bad}} = RetrieveResult.new(%{hits: [], provider: :bad})
    assert {:error, {:invalid_result_metadata, :bad}} = RetrieveResult.new(%{hits: [], metadata: :bad})
    assert {:error, {:invalid_result_extensions, :bad}} = RetrieveResult.new(%{hits: [], extensions: :bad})
    assert {:error, :invalid_retrieve_result} = RetrieveResult.new(:bad)

    assert_raise ArgumentError, ~r/invalid retrieve result/, fn ->
      RetrieveResult.new!(%{hits: :bad})
    end
  end

  test "IngestRequest injects scoped namespaces and validates error branches" do
    assert {:ok, %IngestRequest{records: [%Record{namespace: "agent:scoped"}]}} =
             IngestRequest.new(%{
               records: [
                 %{
                   class: :semantic,
                   kind: :fact,
                   text: "scoped",
                   observed_at: 1
                 }
               ],
               scope: %{namespace: "agent:scoped"}
             })

    assert {:error, {:invalid_ingest_records, :bad}} = IngestRequest.new(%{records: :bad})
    assert {:error, {:invalid_scope, :bad}} = IngestRequest.new(%{records: [], scope: :bad})
    assert {:error, {:invalid_ingest_metadata, :bad}} = IngestRequest.new(%{records: [], metadata: :bad})
    assert {:error, {:invalid_ingest_extensions, :bad}} = IngestRequest.new(%{records: [], extensions: :bad})
    assert {:error, :invalid_ingest_request} = IngestRequest.new(:bad)
  end

  test "IngestResult validates record and metadata branches" do
    assert {:ok, %IngestResult{accepted_count: 0, records: [], metadata: %{}}} =
             IngestResult.new(%{records: [], scope: nil, provider: nil, metadata: nil})

    assert {:error, {:invalid_accepted_count, -1}} = IngestResult.new(%{accepted_count: -1})
    assert {:error, {:invalid_records, :bad}} = IngestResult.new(%{records: :bad})
    assert {:error, {:invalid_ingest_result_record, 123}} = IngestResult.new(%{records: [123]})
    assert {:error, {:invalid_scope, :bad}} = IngestResult.new(%{records: [], scope: :bad})
    assert {:error, {:invalid_provider_info, :bad}} = IngestResult.new(%{records: [], provider: :bad})
    assert {:error, {:invalid_ingest_result_metadata, :bad}} = IngestResult.new(%{records: [], metadata: :bad})
    assert {:error, :invalid_ingest_result} = IngestResult.new(:bad)
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
