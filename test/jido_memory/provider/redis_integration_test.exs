defmodule Jido.Memory.Provider.RedisIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Jido.Memory.{
    ProviderInfo,
    Query,
    Record,
    RetrieveResult,
    Runtime,
    Scope
  }

  alias Jido.Memory.Store.Redis
  alias JidoMemory.Test.LiveRedis

  setup_all do
    assert :ok = LiveRedis.ensure_ready()
    :ok
  end

  setup do
    prefix = LiveRedis.unique_prefix("jido:test:live-provider")
    command_fn = LiveRedis.command_fn()

    on_exit(fn -> :ok = LiveRedis.cleanup_prefix(prefix) end)

    %{prefix: prefix, command_fn: command_fn}
  end

  test "runtime provider :redis works against a live redis server", %{prefix: prefix, command_fn: command_fn} do
    opts = [provider: :redis, provider_opts: [command_fn: command_fn, prefix: prefix]]
    agent = %{id: "live-redis-provider"}

    assert {:ok, %Record{id: id, namespace: "agent:live-redis-provider", content: %{transport: :resp}}} =
             Runtime.remember(
               agent,
               %{
                 class: :semantic,
                 kind: :fact,
                 text: "live redis provider path",
                 tags: ["redis", "runtime"],
                 content: %{transport: :resp}
               },
               opts
             )

    assert {:ok,
            %RetrieveResult{
              scope: %Scope{provider_key: :redis},
              provider: %ProviderInfo{key: :redis},
              hits: [%{record: %Record{id: ^id, text: "live redis provider path"}}]
            }} =
             Runtime.retrieve(agent, Query.new!(%{text_contains: "provider path"}), opts)

    assert {:ok, %ProviderInfo{key: :redis, metadata: %{store: {Redis, store_opts}}}} =
             Runtime.info(agent, opts)

    assert Keyword.get(store_opts, :prefix) == prefix
    assert is_function(Keyword.get(store_opts, :command_fn), 1)

    assert {:ok, true} = Runtime.forget(agent, id, opts)
    assert {:ok, false} = Runtime.forget(agent, id, opts)
  end

  test "runtime basic provider can still target the live redis store explicitly", %{
    prefix: prefix,
    command_fn: command_fn
  } do
    opts = [
      provider: :basic,
      provider_opts: [
        namespace: "agent:basic-live-redis",
        store: {Redis, [command_fn: command_fn, prefix: prefix]}
      ]
    ]

    assert {:ok, %Record{id: id, namespace: "agent:basic-live-redis"}} =
             Runtime.remember(
               %{},
               %{
                 class: :semantic,
                 kind: :fact,
                 text: "basic provider with live redis store"
               },
               opts
             )

    assert {:ok,
            %RetrieveResult{
              provider: %ProviderInfo{key: :basic},
              hits: [%{record: %Record{id: ^id, text: "basic provider with live redis store"}}]
            }} =
             Runtime.retrieve(%{}, Query.new!(%{namespace: "agent:basic-live-redis"}), opts)
  end
end
