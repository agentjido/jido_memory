defmodule Jido.Memory.ProviderBootstrapTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.{ProviderBootstrap, ProviderInfo}

  defmodule BootProvider do
    @behaviour Jido.Memory.Provider

    alias Jido.Memory.{CapabilitySet, ProviderInfo, RetrieveResult}

    @impl true
    def validate_config(opts) when is_list(opts), do: :ok
    def validate_config(_opts), do: {:error, :invalid_provider_opts}

    @impl true
    def capabilities(opts) when is_list(opts) do
      {:ok, CapabilitySet.new!(provider: __MODULE__, capabilities: [:retrieve], metadata: %{provider_opts: opts})}
    end

    @impl true
    def remember(_target, _attrs, _opts), do: {:error, :not_implemented}

    @impl true
    def get(_target, _id, _opts), do: {:error, :not_implemented}

    @impl true
    def retrieve(_target, _query, opts) do
      {:ok, RetrieveResult.new!(provider: info_struct(opts), hits: [], total_count: 0, metadata: %{})}
    end

    @impl true
    def forget(_target, _id, _opts), do: {:ok, false}

    @impl true
    def prune(_target, _opts), do: {:ok, 0}

    @impl true
    def info(opts, _fields) when is_list(opts), do: {:ok, info_struct(opts)}

    @impl true
    def child_specs(opts) when is_list(opts) do
      [
        %{id: {__MODULE__, :worker}, start: {Task, :start_link, [fn -> Process.sleep(:infinity) end]}},
        %{id: {__MODULE__, :opts}, start: {Agent, :start_link, [fn -> opts end]}}
      ]
    end

    defp info_struct(opts) do
      ProviderInfo.new!(%{
        name: "boot_provider",
        provider: __MODULE__,
        description: "Test provider with explicit bootstrap child specs",
        capabilities: [:retrieve],
        metadata: %{provider_opts: opts}
      })
    end
  end

  test "child_specs returns an empty list for the basic provider" do
    assert {:ok, []} = ProviderBootstrap.child_specs(:basic)
  end

  test "bootstrappable reports whether a provider exports child_specs/1" do
    assert ProviderBootstrap.bootstrappable?(:basic)
    assert ProviderBootstrap.bootstrappable?(BootProvider)
    refute ProviderBootstrap.bootstrappable?(:not_a_provider)
  end

  test "child_specs returns validated provider-owned child specs" do
    assert {:ok, child_specs} =
             ProviderBootstrap.child_specs({BootProvider, [namespace: "agent:boot"]})

    assert length(child_specs) == 2
  end

  test "describe returns provider metadata and caller-owned bootstrap details" do
    assert {:ok, description} =
             ProviderBootstrap.describe({BootProvider, [namespace: "agent:boot"]})

    assert description.provider == BootProvider
    assert description.opts == [namespace: "agent:boot"]
    assert description.ownership == :caller
    assert is_list(description.child_specs)
    assert %ProviderInfo{name: "boot_provider", provider: BootProvider} = description.provider_info
  end
end
