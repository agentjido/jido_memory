defmodule Jido.Memory.RuntimeTest do
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

  alias Jido.Memory.Store.ETS

  defmodule NeutralProvider do
    @behaviour Jido.Memory.Provider

    def validate_config(opts) when is_list(opts), do: :ok
    def capabilities(_opts), do: {:ok, CapabilitySet.new!(provider: __MODULE__, capabilities: [:retrieve])}

    def info(opts, _fields),
      do:
        {:ok,
         ProviderInfo.new!(provider: __MODULE__, name: "neutral", capabilities: [:retrieve], metadata: %{opts: opts})}

    def remember(_target, attrs, _opts) do
      {:ok,
       Record.new!(%{
         namespace: attrs[:namespace] || "agent:neutral",
         class: :semantic,
         kind: :fact,
         text: attrs[:text] || "neutral",
         observed_at: 1
       })}
    end

    def get(_target, id, _opts) do
      {:ok,
       Record.new!(%{
         id: id,
         namespace: "agent:neutral",
         class: :semantic,
         kind: :fact,
         text: "neutral",
         observed_at: 1
       })}
    end

    def retrieve(_target, _query, _opts), do: {:ok, RetrieveResult.new!(hits: [], total_count: 0)}
    def forget(_target, _id, _opts), do: {:ok, false}
    def prune(_target, _opts), do: {:ok, 0}
  end

  setup do
    table = String.to_atom("jido_memory_facade_test_#{System.unique_integer([:positive])}")
    opts = [table: table]
    assert :ok = ETS.ensure_ready(opts)
    %{store: {ETS, opts}, opts: opts}
  end

  test "remember/get/forget with explicit namespace", %{store: store} do
    attrs = %{
      namespace: "agent:explicit",
      class: :semantic,
      kind: :fact,
      text: "Elixir runs on the BEAM",
      tags: ["elixir", "beam"]
    }

    assert {:ok, %Record{id: id}} = Runtime.remember(%{}, attrs, store: store)

    assert {:ok, %Record{id: ^id, namespace: "agent:explicit"}} =
             Runtime.get(%{}, id, namespace: "agent:explicit", store: store)

    assert {:ok, true} =
             Runtime.forget(%{}, id, namespace: "agent:explicit", store: store)

    assert {:error, :not_found} =
             Runtime.get(%{}, id, namespace: "agent:explicit", store: store)
  end

  test "retrieve returns canonical results", %{store: store} do
    assert {:ok, %Record{id: id}} =
             Runtime.remember(
               %{id: "agent-a"},
               %{class: :episodic, kind: :event, text: "A1"},
               store: store
             )

    assert {:ok, %RetrieveResult{hits: [%{record: %Record{id: ^id, namespace: "agent:agent-a"}}]}} =
             Runtime.retrieve(%{id: "agent-a"}, %{store: store, order: :asc})
  end

  test "retrieve falls back to plugin namespace when query namespace is nil", %{store: store} do
    agent = %{
      id: "agent-plugin",
      state: %{
        __memory__: %{
          namespace: "agent:agent-plugin",
          store: store
        }
      }
    }

    assert {:ok, %Record{id: id}} =
             Runtime.remember(
               agent,
               %{class: :episodic, kind: :event, text: "plugin scoped retrieval"},
               store: store
             )

    assert {:ok, %RetrieveResult{hits: [%{record: %Record{id: ^id, namespace: "agent:agent-plugin"}}]}} =
             Runtime.retrieve(agent, %{namespace: nil, text_contains: "plugin", order: :asc})
  end

  test "embedding metadata is stored and retrievable", %{store: store} do
    assert {:ok, %Record{id: id}} =
             Runtime.remember(
               %{},
               %{
                 namespace: "agent:embedding",
                 class: :semantic,
                 kind: :fact,
                 text: "vector ready",
                 embedding: [0.12, 0.98, 0.44],
                 metadata: %{provider: "none"}
               },
               store: store
             )

    assert {:ok, %Record{embedding: [0.12, 0.98, 0.44], metadata: %{provider: "none"}}} =
             Runtime.get(%{}, id, namespace: "agent:embedding", store: store)
  end

  test "provider options can configure runtime behavior and alias resolution", %{store: store} do
    assert {:ok, %Record{namespace: "provider:agent-a"}} =
             Runtime.remember(
               %{id: "agent-a"},
               %{
                 class: :episodic,
                 kind: :event,
                 text: "provider config path"
               },
               provider: :basic,
               provider_opts: [namespace: "provider:agent-a", store: store]
             )

    assert {:ok, %RetrieveResult{} = result} =
             Runtime.retrieve(
               %{id: "agent-a"},
               %{provider: :basic, provider_opts: [namespace: "provider:agent-a", store: store]}
             )

    assert [%{record: %Record{text: "provider config path"}} | _] = result.hits
    assert result.scope.namespace == "provider:agent-a"
    assert result.provider.metadata.store == store
  end

  test "capabilities and info return canonical structs", %{store: store} do
    assert {:ok, %CapabilitySet{provider: Jido.Memory.Provider.Basic} = capability_set} =
             Runtime.capabilities(%{}, provider: :basic, provider_opts: [store: store])

    assert capability_set.key == :basic
    assert CapabilitySet.supports?(capability_set, :retrieve)
    assert CapabilitySet.supports?(capability_set, :ingest)
    assert CapabilitySet.supports?(capability_set, [:retrieval, :explainable])
    assert CapabilitySet.get(capability_set, [:lifecycle, :consolidate]) == true

    assert {:ok, %ProviderInfo{name: "basic", key: :basic, provider: Jido.Memory.Provider.Basic} = info} =
             Runtime.info(%{}, provider: :basic, provider_opts: [store: store])

    assert info.capability_descriptor.ingestion.batch == true
    assert info.surface_boundary.plugin == Jido.Memory.BasicPlugin

    assert {:ok, %{name: "basic", capabilities: capabilities}} =
             Runtime.info(%{}, [provider: :basic, provider_opts: [store: store]], [:name, :capabilities])

    assert :retrieve in capabilities
  end

  test "optional provider capabilities are exposed through canonical runtime wrappers", %{store: store} do
    assert {:ok, %IngestResult{accepted_count: 2, records: [%Record{}, %Record{}]}} =
             Runtime.ingest(
               %{id: "agent-ingest"},
               %{
                 records: [
                   %{
                     namespace: "agent:ingest",
                     class: :semantic,
                     kind: :fact,
                     text: "First"
                   },
                   %{
                     namespace: "agent:ingest",
                     class: :semantic,
                     kind: :fact,
                     text: "Second"
                   }
                 ]
               },
               provider: :basic,
               provider_opts: [store: store]
             )

    assert {:ok, %Explanation{summary: summary}} =
             Runtime.explain_retrieval(
               %{id: "agent-ingest"},
               %{namespace: "agent:ingest", text_contains: "First"},
               provider: :basic,
               provider_opts: [store: store]
             )

    assert summary =~ "hit"

    assert {:ok, %ConsolidationResult{status: :ok}} =
             Runtime.consolidate(
               %{id: "agent-ingest"},
               provider: :basic,
               provider_opts: [store: store]
             )
  end

  test "resolve_provider folds runtime namespace and store into basic provider opts", %{store: store} do
    assert {:ok, {Jido.Memory.Provider.Basic, provider_opts}} =
             Runtime.resolve_provider(%{}, %{namespace: "agent:compat"}, store: store)

    assert Keyword.get(provider_opts, :store) == store
    assert Keyword.get(provider_opts, :namespace) == "agent:compat"
  end

  test "resolve_provider keeps non-basic providers free of store-specific defaults", %{store: store} do
    agent = %{
      id: "agent-neutral",
      state: %{
        __memory__: %{
          namespace: "agent:agent-neutral",
          store: store
        }
      }
    }

    assert {:ok, {NeutralProvider, provider_opts}} =
             Runtime.resolve_provider(agent, %{},
               provider: NeutralProvider,
               store: store,
               store_opts: [table: :ignored]
             )

    assert Keyword.get(provider_opts, :namespace) == "agent:agent-neutral"
    refute Keyword.has_key?(provider_opts, :store)
    refute Keyword.has_key?(provider_opts, :store_opts)
  end

  test "invalid provider option container fails fast", %{store: store} do
    assert {:error, :invalid_provider_opts} =
             Runtime.remember(
               %{},
               %{
                 class: :episodic,
                 kind: :event,
                 text: "bad provider opts",
                 namespace: "agent:invalid"
               },
               provider: Jido.Memory.Provider.Basic,
               provider_opts: :bad_opts,
               store: store
             )
  end
end
