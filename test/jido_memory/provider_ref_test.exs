defmodule Jido.Memory.ProviderRefTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.ProviderRef

  defmodule MissingBehaviorProvider do
    @moduledoc false
    def validate_config(_opts), do: :ok
  end

  test "normalizes nil provider as Basic with default opts" do
    assert {:ok, %{key: :basic, module: Jido.Memory.Provider.Basic, opts: []}} = ProviderRef.normalize(nil)
  end

  test "normalizes explicit provider module and tuple providers" do
    opts = [namespace: "agent:test", store: {Jido.Memory.Store.ETS, [table: :jido_memory_ref_test]}]

    assert {:ok, %{key: :basic, module: Jido.Memory.Provider.Basic, opts: ^opts}} =
             ProviderRef.normalize({Jido.Memory.Provider.Basic, opts})

    assert {:ok, %{key: :basic, module: Jido.Memory.Provider.Basic, opts: ^opts}} =
             ProviderRef.normalize({:basic, opts})

    assert {:ok, %{key: :basic, module: Jido.Memory.Provider.Basic, opts: []}} =
             ProviderRef.normalize(Jido.Memory.Provider.Basic)

    assert {:ok, %{key: :basic, module: Jido.Memory.Provider.Basic, opts: []}} = ProviderRef.normalize(:basic)
  end

  test "validates required callbacks and config hook" do
    assert {:ok, %{module: Jido.Memory.Provider.Basic}} =
             ProviderRef.validate(%ProviderRef{module: Jido.Memory.Provider.Basic, opts: []})
  end

  test "rejects providers without required behavior" do
    assert {:error, {:invalid_provider, {MissingBehaviorProvider, missing_callbacks}}} =
             ProviderRef.validate(%ProviderRef{
               module: MissingBehaviorProvider,
               opts: []
             })

    assert is_list(missing_callbacks)
  end

  test "normalization rejects malformed provider values" do
    assert {:error, {:provider_not_loaded, :not_a_provider, _}} = ProviderRef.normalize(:not_a_provider)
    assert {:error, :invalid_provider} = ProviderRef.normalize({Jido.Memory.Provider.Basic, :not_a_opts})
    assert {:error, :invalid_provider} = ProviderRef.normalize(%{module: Jido.Memory.Provider.Basic})
  end
end
