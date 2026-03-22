defmodule Jido.Memory.ProviderBootstrapTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.ProviderBootstrap
  alias Jido.Memory.Support.ExternalProvider

  test "built-in providers remain process-neutral by default" do
    assert {:ok, []} = ProviderBootstrap.child_specs(Basic)
    assert {:ok, []} = ProviderBootstrap.child_specs(Tiered)
  end

  test "external providers expose caller-owned bootstrap requirements" do
    assert {:ok, child_specs} =
             ProviderBootstrap.child_specs(
               {ExternalProvider, [store: {Jido.Memory.Store.ETS, [table: :bootstrap_test]}]}
             )

    assert length(child_specs) == 1

    assert {:ok, description} =
             ProviderBootstrap.describe(
               {ExternalProvider,
                [store: {Jido.Memory.Store.ETS, [table: :bootstrap_test]}, namespace: "provider:bootstrap"]}
             )

    assert description.provider == ExternalProvider
    assert description.ownership == :caller
    assert length(description.child_specs) == 1
    assert description.provider_meta.bootstrap.ownership == :caller
  end
end
