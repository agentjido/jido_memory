defmodule Jido.Memory.ProviderRegistryTest do
  use ExUnit.Case, async: false

  alias Jido.Memory.{CapabilitySet, ProviderInfo, ProviderRegistry, Record, RetrieveResult, Runtime}

  defmodule CustomProvider do
    @moduledoc false

    @behaviour Jido.Memory.Provider

    def validate_config(opts) when is_list(opts), do: :ok
    def capabilities(_opts), do: {:ok, CapabilitySet.new!(provider: __MODULE__, capabilities: [:retrieve])}

    def info(_opts, _fields),
      do: {:ok, ProviderInfo.new!(provider: __MODULE__, name: "custom", capabilities: [:retrieve])}

    def remember(_target, attrs, _opts) do
      {:ok,
       Record.new!(%{
         namespace: attrs[:namespace] || "agent:custom",
         class: :semantic,
         kind: :fact,
         text: attrs[:text] || "custom",
         observed_at: 1
       })}
    end

    def get(_target, id, _opts) do
      {:ok,
       Record.new!(%{
         id: id,
         namespace: "agent:custom",
         class: :semantic,
         kind: :fact,
         text: "custom",
         observed_at: 1
       })}
    end

    def retrieve(_target, _query, _opts), do: {:ok, RetrieveResult.new!(hits: [], total_count: 0)}
    def forget(_target, _id, _opts), do: {:ok, false}
    def prune(_target, _opts), do: {:ok, 0}
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

  test "built-in aliases resolve and unknown atoms fail explicitly" do
    assert ProviderRegistry.built_in_aliases()[:basic] == Jido.Memory.Provider.Basic
    assert ProviderRegistry.alias?(:basic)
    assert {:ok, Jido.Memory.Provider.Basic} = ProviderRegistry.resolve(:basic)
    assert ProviderRegistry.resolve!(Jido.Memory.Provider.Basic) == Jido.Memory.Provider.Basic
    assert ProviderRegistry.key_for(:basic) == :basic
    assert ProviderRegistry.key_for(Jido.Memory.Provider.Basic) == :basic
    assert {:error, {:unknown_provider, :unknown_provider}} = ProviderRegistry.resolve(:unknown_provider)
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

  test "runtime backfills canonical provider keys for aliased providers" do
    Application.put_env(:jido_memory, :provider_aliases, custom: CustomProvider)

    assert {:ok, %CapabilitySet{provider: CustomProvider, key: :custom}} =
             Runtime.capabilities(%{}, provider: :custom)

    assert {:ok, %ProviderInfo{provider: CustomProvider, key: :custom}} =
             Runtime.info(%{}, provider: :custom)
  end
end
