defmodule Jido.Memory.RedisProviderContractTest do
  use ExUnit.Case, async: true
  use Jido.Memory.Testing.ProviderContractCase

  alias Jido.Memory.Provider.Redis
  alias JidoMemory.Test.MockRedis

  setup do
    {:ok, pid} = MockRedis.start_link()

    %{
      provider_opts: [
        namespace: "agent:provider-contract-redis",
        store_opts: [
          command_fn: MockRedis.command_fn(pid),
          prefix: "jido:provider:contract:#{System.unique_integer([:positive])}"
        ]
      ]
    }
  end

  def provider_under_test, do: Redis
  def provider_target(_context), do: %{id: "provider-contract-redis-agent"}
  def provider_opts(context), do: context.provider_opts

  def remember_attrs(context) do
    %{
      namespace: context.provider_opts[:namespace],
      class: :semantic,
      kind: :fact,
      text: "redis provider contract memory",
      tags: ["contract", "provider", "redis"]
    }
  end
end
