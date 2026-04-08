defmodule Jido.Memory.ProviderRegistryTest do
  use ExUnit.Case, async: false

  alias Jido.Memory.ProviderRegistry

  defmodule CustomProvider do
    @moduledoc false
  end

  setup do
    previous = Application.get_env(:jido_memory, :provider_aliases)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:jido_memory, :provider_aliases)
      else
        Application.put_env(:jido_memory, :provider_aliases, previous)
      end
    end)

    :ok
  end

  test "built-in aliases resolve and unknown atoms pass through" do
    assert ProviderRegistry.built_in_aliases()[:basic] == Jido.Memory.Provider.Basic
    assert ProviderRegistry.alias?(:basic)
    assert {:ok, Jido.Memory.Provider.Basic} = ProviderRegistry.resolve(:basic)
    assert ProviderRegistry.resolve!(Jido.Memory.Provider.Basic) == Jido.Memory.Provider.Basic
    assert ProviderRegistry.key_for(:basic) == :basic
    assert ProviderRegistry.key_for(Jido.Memory.Provider.Basic) == :basic
    assert {:ok, :unknown_provider} = ProviderRegistry.resolve(:unknown_provider)
    refute ProviderRegistry.alias?(:unknown_provider)
    refute ProviderRegistry.alias?("basic")
  end

  test "configured aliases merge with but do not override built-ins" do
    Application.put_env(:jido_memory, :provider_aliases, basic: CustomProvider, custom: CustomProvider)

    assert ProviderRegistry.alias?(:custom)
    assert ProviderRegistry.aliases()[:custom] == CustomProvider
    assert ProviderRegistry.aliases()[:basic] == Jido.Memory.Provider.Basic

    assert {:ok, CustomProvider} = ProviderRegistry.resolve(:custom)
    assert {:ok, Jido.Memory.Provider.Basic} = ProviderRegistry.resolve(:basic)
    assert ProviderRegistry.key_for(CustomProvider) == :custom
  end
end
