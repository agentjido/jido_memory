defmodule Jido.Memory.Testing.ProviderContractCase do
  @moduledoc """
  Reusable provider compatibility tests for `jido_memory` providers.

  External provider packages can use this in their test suite:

      defmodule MyProviderContractTest do
        use ExUnit.Case, async: true
        use Jido.Memory.Testing.ProviderContractCase

        def provider_under_test, do: Jido.Memory.Provider.MyProvider
        def provider_opts, do: [namespace: "agent:test"]
      end
  """

  @doc """
  Defines the shared provider contract tests.
  """
  defmacro __using__(_opts) do
    quote do
      @doc false
      def provider_under_test, do: raise("provider_under_test/0 must be defined")

      @doc false
      def provider_opts(_context), do: []

      @doc false
      def provider_target(_context), do: %{id: "provider-contract-agent"}

      @doc false
      def remember_attrs(_context) do
        %{
          namespace: "agent:provider-contract",
          class: :semantic,
          kind: :fact,
          text: "provider contract memory",
          tags: ["contract", "provider"]
        }
      end

      defoverridable provider_under_test: 0, provider_opts: 1, provider_target: 1, remember_attrs: 1

      test "provider exposes canonical capabilities", context do
        assert {:ok, %Jido.Memory.CapabilitySet{provider: provider}} =
                 Jido.Memory.Runtime.capabilities(provider_target(context),
                   provider: provider_under_test(),
                   provider_opts: provider_opts(context)
                 )

        assert provider == provider_under_test()
      end

      test "provider exposes canonical info", context do
        assert {:ok, %Jido.Memory.ProviderInfo{provider: provider}} =
                 Jido.Memory.Runtime.info(provider_target(context),
                   provider: provider_under_test(),
                   provider_opts: provider_opts(context)
                 )

        assert provider == provider_under_test()
      end

      test "provider supports remember/get/retrieve/forget core flow", context do
        attrs = remember_attrs(context)

        assert {:ok, %Jido.Memory.Record{id: id}} =
                 Jido.Memory.Runtime.remember(provider_target(context), attrs,
                   provider: provider_under_test(),
                   provider_opts: provider_opts(context)
                 )

        namespace = Map.fetch!(attrs, :namespace)

        assert {:ok, %Jido.Memory.Record{id: ^id}} =
                 Jido.Memory.Runtime.get(provider_target(context), id,
                   provider: provider_under_test(),
                   provider_opts: Keyword.put_new(provider_opts(context), :namespace, namespace)
                 )

        assert {:ok, %Jido.Memory.RetrieveResult{hits: [%{record: %Jido.Memory.Record{id: ^id}} | _]}} =
                 Jido.Memory.Runtime.retrieve(
                   provider_target(context),
                   %{namespace: namespace, text_contains: attrs.text},
                   provider: provider_under_test(),
                   provider_opts: provider_opts(context)
                 )

        assert {:ok, true} =
                 Jido.Memory.Runtime.forget(provider_target(context), id,
                   provider: provider_under_test(),
                   provider_opts: Keyword.put_new(provider_opts(context), :namespace, namespace)
                 )
      end

      test "retrieve results expose canonical records through RetrieveResult.records/1", context do
        attrs = remember_attrs(context)

        assert {:ok, %Jido.Memory.Record{text: text}} =
                 Jido.Memory.Runtime.remember(provider_target(context), attrs,
                   provider: provider_under_test(),
                   provider_opts: provider_opts(context)
                 )

        assert text == attrs.text

        assert {:ok, %Jido.Memory.RetrieveResult{} = result} =
                 Jido.Memory.Runtime.retrieve(provider_target(context), %{namespace: attrs.namespace},
                   provider: provider_under_test(),
                   provider_opts: provider_opts(context)
                 )

        assert [%Jido.Memory.Record{text: retrieved_text} | _] = Jido.Memory.RetrieveResult.records(result)
        assert retrieved_text == attrs.text
      end

      test "optional capabilities use canonical result structs when supported", context do
        attrs = remember_attrs(context)

        assert {:ok, %Jido.Memory.CapabilitySet{} = capabilities} =
                 Jido.Memory.Runtime.capabilities(provider_target(context),
                   provider: provider_under_test(),
                   provider_opts: provider_opts(context)
                 )

        if Jido.Memory.CapabilitySet.supports?(capabilities, :ingest) do
          assert {:ok, %Jido.Memory.IngestResult{}} =
                   Jido.Memory.Runtime.ingest(provider_target(context), %{records: [attrs]},
                     provider: provider_under_test(),
                     provider_opts: provider_opts(context)
                   )
        end

        if Jido.Memory.CapabilitySet.supports?(capabilities, :explain_retrieval) do
          assert {:ok, %Jido.Memory.Explanation{}} =
                   Jido.Memory.Runtime.explain_retrieval(provider_target(context), %{namespace: attrs.namespace},
                     provider: provider_under_test(),
                     provider_opts: provider_opts(context)
                   )
        end

        if Jido.Memory.CapabilitySet.supports?(capabilities, :consolidate) do
          assert {:ok, %Jido.Memory.ConsolidationResult{}} =
                   Jido.Memory.Runtime.consolidate(provider_target(context),
                     provider: provider_under_test(),
                     provider_opts: provider_opts(context)
                   )
        end
      end
    end
  end
end
