defmodule Jido.Memory.ConsolidationResultTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.{ConsolidationResult, ProviderInfo, Scope}

  test "builds normalized consolidation results" do
    assert {:ok, %ConsolidationResult{} = result} =
             ConsolidationResult.new(%{
               scope: %{namespace: "agent:test", provider: Jido.Memory.Provider.Basic},
               provider: %{provider: Jido.Memory.Provider.Basic, capabilities: [:consolidate]},
               status: :ok,
               consolidated_count: 2,
               pruned_count: 1,
               metadata: %{strategy: "ttl"},
               extensions: %{provider_latency_ms: 4}
             })

    assert %Scope{namespace: "agent:test"} = result.scope
    assert %ProviderInfo{provider: Jido.Memory.Provider.Basic} = result.provider
    assert result.status == :ok
    assert result.consolidated_count == 2
    assert result.pruned_count == 1
    assert result.metadata.strategy == "ttl"
    assert result.extensions.provider_latency_ms == 4
  end

  test "validates invalid consolidation result values" do
    assert {:error, {:invalid_scope, :bad}} = ConsolidationResult.new(%{scope: :bad})
    assert {:error, {:invalid_provider_info, :bad}} = ConsolidationResult.new(%{provider: :bad})
    assert {:error, {:invalid_consolidation_status, "ok"}} = ConsolidationResult.new(%{status: "ok"})
    assert {:error, {:invalid_consolidated_count, -1}} = ConsolidationResult.new(%{consolidated_count: -1})
    assert {:error, {:invalid_pruned_count, -1}} = ConsolidationResult.new(%{pruned_count: -1})
    assert {:error, {:invalid_consolidation_metadata, :bad}} = ConsolidationResult.new(%{metadata: :bad})
    assert {:error, {:invalid_consolidation_extensions, :bad}} = ConsolidationResult.new(%{extensions: :bad})
    assert {:error, :invalid_consolidation_result} = ConsolidationResult.new(:bad)

    assert_raise ArgumentError, ~r/invalid consolidation result/, fn ->
      ConsolidationResult.new!(%{status: "bad"})
    end
  end
end
