defmodule Jido.Memory.RuntimeNormalizationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.{
    CapabilitySet,
    ConsolidationResult,
    Explanation,
    IngestResult,
    ProviderInfo,
    Record,
    RetrieveResult,
    Runtime
  }

  defmodule ShapeProvider do
    @behaviour Jido.Memory.Provider

    def validate_config(opts) when is_list(opts), do: :ok

    def capabilities(_opts), do: {:ok, [:retrieve, :ingest, :explain_retrieval, :consolidate]}

    def info(_opts, _fields) do
      {:ok, %{name: "shape_provider", capabilities: [:retrieve], metadata: %{mode: :shape}}}
    end

    def remember(_target, attrs, _opts) do
      {:ok,
       Record.new!(%{
         namespace: attrs[:namespace] || "agent:shape",
         class: attrs[:class] || :semantic,
         kind: attrs[:kind] || :fact,
         text: attrs[:text] || "shape",
         observed_at: 1
       })}
    end

    def get(_target, id, _opts) do
      {:ok,
       Record.new!(%{
         id: id,
         namespace: "agent:shape",
         class: :semantic,
         kind: :fact,
         text: "shape get",
         observed_at: 1
       })}
    end

    def retrieve(_target, _query, _opts) do
      {:ok,
       [
         Record.new!(%{
           namespace: "agent:shape",
           class: :semantic,
           kind: :fact,
           text: "shape retrieve",
           observed_at: 1
         })
       ]}
    end

    def forget(_target, _id, _opts), do: {:ok, true}
    def prune(_target, _opts), do: {:ok, 3}

    def ingest(_target, _request, _opts) do
      {:ok,
       %{
         accepted_count: 1,
         records: [
           %{
             namespace: "agent:shape",
             class: :semantic,
             kind: :fact,
             text: "ingested",
             observed_at: 1
           }
         ],
         metadata: %{path: :map}
       }}
    end

    def explain_retrieval(_target, _query, _opts) do
      {:ok, %{summary: "shape explanation", reasons: [%{path: :map}], metadata: %{mode: :shape}}}
    end

    def consolidate(_target, _opts) do
      {:ok, %{status: :ok, pruned_count: 2, consolidated_count: 1, metadata: %{mode: :shape}}}
    end

    def child_specs(_opts), do: []
  end

  defmodule BareProvider do
    @behaviour Jido.Memory.Provider

    def validate_config(opts) when is_list(opts), do: :ok
    def capabilities(_opts), do: {:ok, CapabilitySet.new!(provider: __MODULE__, capabilities: [:retrieve])}

    def info(_opts, _fields),
      do: {:ok, ProviderInfo.new!(provider: __MODULE__, name: "bare", capabilities: [:retrieve])}

    def remember(_target, attrs, _opts) do
      {:ok,
       Record.new!(%{
         namespace: attrs[:namespace] || "agent:bare",
         class: :semantic,
         kind: :fact,
         text: attrs[:text] || "bare",
         observed_at: 1
       })}
    end

    def get(_target, id, _opts) do
      {:ok,
       Record.new!(%{
         id: id,
         namespace: "agent:bare",
         class: :semantic,
         kind: :fact,
         text: "bare",
         observed_at: 1
       })}
    end

    def retrieve(_target, _query, _opts), do: {:ok, RetrieveResult.new!(hits: [], total_count: 0)}
    def forget(_target, _id, _opts), do: {:ok, false}
    def prune(_target, _opts), do: {:ok, 0}
  end

  defmodule CallbackOnlyProvider do
    @behaviour Jido.Memory.Provider

    def validate_config(opts) when is_list(opts), do: :ok
    def capabilities(_opts), do: {:ok, CapabilitySet.new!(provider: __MODULE__, capabilities: [:retrieve])}

    def info(_opts, _fields),
      do: {:ok, ProviderInfo.new!(provider: __MODULE__, name: "callback_only", capabilities: [:retrieve])}

    def remember(_target, attrs, _opts) do
      {:ok,
       Record.new!(%{
         namespace: attrs[:namespace] || "agent:callback",
         class: :semantic,
         kind: :fact,
         text: attrs[:text] || "callback",
         observed_at: 1
       })}
    end

    def get(_target, id, _opts) do
      {:ok,
       Record.new!(%{
         id: id,
         namespace: "agent:callback",
         class: :semantic,
         kind: :fact,
         text: "callback",
         observed_at: 1
       })}
    end

    def retrieve(_target, _query, _opts), do: {:ok, RetrieveResult.new!(hits: [], total_count: 0)}
    def forget(_target, _id, _opts), do: {:ok, false}
    def prune(_target, _opts), do: {:ok, 0}

    def ingest(_target, _request, _opts) do
      {:ok, %{accepted_count: 1, records: [], metadata: %{mode: :unexpected}}}
    end
  end

  defmodule MismatchProvider do
    @behaviour Jido.Memory.Provider

    def validate_config(opts) when is_list(opts), do: :ok
    def capabilities(_opts), do: {:ok, CapabilitySet.new!(provider: __MODULE__, capabilities: [:retrieve, :ingest])}

    def info(_opts, _fields),
      do: {:ok, ProviderInfo.new!(provider: __MODULE__, name: "mismatch", capabilities: [:retrieve, :ingest])}

    def remember(_target, attrs, _opts) do
      {:ok,
       Record.new!(%{
         namespace: attrs[:namespace] || "agent:mismatch",
         class: :semantic,
         kind: :fact,
         text: attrs[:text] || "mismatch",
         observed_at: 1
       })}
    end

    def get(_target, id, _opts) do
      {:ok,
       Record.new!(%{
         id: id,
         namespace: "agent:mismatch",
         class: :semantic,
         kind: :fact,
         text: "mismatch",
         observed_at: 1
       })}
    end

    def retrieve(_target, _query, _opts), do: {:ok, RetrieveResult.new!(hits: [], total_count: 0)}
    def forget(_target, _id, _opts), do: {:ok, false}
    def prune(_target, _opts), do: {:ok, 0}
  end

  defmodule MalformedProvider do
    @behaviour Jido.Memory.Provider

    def validate_config(opts) when is_list(opts), do: :ok
    def capabilities(_opts), do: {:ok, :bad}
    def info(_opts, _fields), do: {:ok, :bad}
    def remember(_target, _attrs, _opts), do: {:ok, :bad}
    def get(_target, _id, _opts), do: {:ok, :bad}
    def retrieve(_target, _query, _opts), do: {:ok, :bad}
    def forget(_target, _id, _opts), do: {:ok, false}
    def prune(_target, _opts), do: {:ok, 0}
    def ingest(_target, _request, _opts), do: {:ok, :bad}
    def explain_retrieval(_target, _query, _opts), do: {:ok, :bad}
    def consolidate(_target, _opts), do: {:ok, :bad}
  end

  test "runtime normalizes provider list and map shapes" do
    assert {:ok, %CapabilitySet{} = capabilities} =
             Runtime.capabilities(%{}, provider: ShapeProvider)

    assert CapabilitySet.supports?(capabilities, :retrieve)
    assert CapabilitySet.supports?(capabilities, :ingest)
    assert CapabilitySet.supports?(capabilities, :explain_retrieval)
    assert CapabilitySet.supports?(capabilities, :consolidate)

    assert {:ok, %ProviderInfo{name: "shape_provider", metadata: %{mode: :shape}}} =
             Runtime.info(%{}, provider: ShapeProvider)

    assert {:ok, %RetrieveResult{hits: [%{record: %Record{text: "shape retrieve"}}], total_count: 1}} =
             Runtime.retrieve(%{}, %{namespace: "agent:shape"}, provider: ShapeProvider)

    assert {:ok, %IngestResult{accepted_count: 1, metadata: %{path: :map}}} =
             Runtime.ingest(%{}, %{records: []}, provider: ShapeProvider)

    assert {:ok, %Explanation{summary: "shape explanation", metadata: %{mode: :shape}}} =
             Runtime.explain_retrieval(%{}, %{namespace: "agent:shape"}, provider: ShapeProvider)

    assert {:ok, %ConsolidationResult{status: :ok, consolidated_count: 1, pruned_count: 2}} =
             Runtime.consolidate(%{}, provider: ShapeProvider)

    assert {:ok, 3} = Runtime.prune_expired(%{}, provider: ShapeProvider)
  end

  test "runtime returns unsupported capability errors when optional callbacks are missing" do
    assert {:error, {:unsupported_capability, :ingest, BareProvider}} =
             Runtime.ingest(%{}, %{records: []}, provider: BareProvider)

    assert {:error, {:unsupported_capability, :explain_retrieval, BareProvider}} =
             Runtime.explain_retrieval(%{}, %{namespace: "agent:bare"}, provider: BareProvider)

    assert {:error, {:unsupported_capability, :consolidate, BareProvider}} =
             Runtime.consolidate(%{}, provider: BareProvider)
  end

  test "runtime uses CapabilitySet as the authority for optional operations" do
    assert {:error, {:unsupported_capability, :ingest, CallbackOnlyProvider}} =
             Runtime.ingest(%{}, %{records: []}, provider: CallbackOnlyProvider)

    assert {:error, {:invalid_provider_capability, :ingest, MismatchProvider}} =
             Runtime.ingest(%{}, %{records: []}, provider: MismatchProvider)
  end

  test "runtime surfaces malformed provider payloads as canonical errors" do
    assert {:error, {:invalid_capability_set, :bad}} = Runtime.capabilities(%{}, provider: MalformedProvider)
    assert {:error, {:invalid_provider_info, :bad}} = Runtime.info(%{}, provider: MalformedProvider)

    assert {:error, {:invalid_retrieve_result, :bad}} =
             Runtime.retrieve(%{}, %{namespace: "agent:test"}, provider: MalformedProvider)

    assert {:error, {:invalid_capability_set, :bad}} = Runtime.ingest(%{}, %{records: []}, provider: MalformedProvider)

    assert {:error, {:invalid_capability_set, :bad}} =
             Runtime.explain_retrieval(%{}, %{namespace: "agent:test"}, provider: MalformedProvider)

    assert {:error, {:invalid_capability_set, :bad}} = Runtime.consolidate(%{}, provider: MalformedProvider)
  end

  test "runtime validates invalid public inputs" do
    assert {:error, :invalid_query} = Runtime.retrieve(%{}, :bad)
    assert {:error, :invalid_ingest_request} = Runtime.ingest(%{}, :bad)
    assert {:error, :invalid_query} = Runtime.explain_retrieval(%{}, :bad)
  end
end
