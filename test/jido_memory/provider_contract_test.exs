defmodule Jido.Memory.BasicProviderContractTest do
  use ExUnit.Case, async: true
  use Jido.Memory.Testing.ProviderContractCase

  alias Jido.Memory.Store.ETS

  setup do
    table = String.to_atom("jido_memory_provider_contract_#{System.unique_integer([:positive])}")
    opts = [table: table, namespace: "agent:provider-contract"]
    assert :ok = ETS.ensure_ready(table: table)
    %{provider_opts: opts}
  end

  def provider_under_test, do: Jido.Memory.Provider.Basic
  def provider_target(_context), do: %{id: "provider-contract-agent"}

  def provider_opts(context),
    do: [store: {ETS, [table: context.provider_opts[:table]]}, namespace: context.provider_opts[:namespace]]

  def remember_attrs(context) do
    %{
      namespace: context.provider_opts[:namespace],
      class: :semantic,
      kind: :fact,
      text: "provider contract memory",
      tags: ["contract", "provider"]
    }
  end
end
