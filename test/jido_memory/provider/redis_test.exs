defmodule Jido.Memory.Provider.RedisTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.{
    ConsolidationResult,
    Explanation,
    IngestRequest,
    IngestResult,
    ProviderInfo,
    Query,
    Record,
    RetrieveResult,
    Runtime,
    Scope
  }

  alias Jido.Memory.Provider.Redis
  alias JidoMemory.Test.MockRedis

  setup do
    {:ok, pid} = MockRedis.start_link()

    provider_opts = [
      namespace: "agent:redis",
      store_opts: [
        command_fn: MockRedis.command_fn(pid),
        prefix: "jido:provider:redis:#{System.unique_integer([:positive])}"
      ]
    ]

    %{pid: pid, provider_opts: provider_opts}
  end

  test "validate_config child_specs capabilities and info", %{provider_opts: provider_opts} do
    assert :ok = Redis.validate_config(provider_opts)
    assert {:error, :invalid_namespace} = Redis.validate_config(namespace: 123, store_opts: [])
    assert {:error, :invalid_store} = Redis.validate_config(namespace: "agent:test", store: Jido.Memory.Store.ETS)
    assert {:error, :invalid_store_opts} = Redis.validate_config(namespace: "agent:test", store_opts: :bad)
    assert {:error, :invalid_provider_opts} = Redis.validate_config(:bad)
    assert [] == Redis.child_specs([])

    assert {:ok, capability_set} = Redis.capabilities(provider_opts)
    assert capability_set.key == :redis
    assert capability_set.provider == Redis
    assert :retrieve in capability_set.capabilities

    assert {:ok, %ProviderInfo{name: "redis", key: :redis, provider: Redis} = info} =
             Redis.info(provider_opts, :all)

    assert match?({Jido.Memory.Store.Redis, _}, info.metadata.store)
    assert info.surface_boundary.common_runtime != []
  end

  test "remember get retrieve and forget keep redis provider identity", %{provider_opts: provider_opts} do
    agent = %{id: "redis-agent"}
    target_opts = Keyword.delete(provider_opts, :namespace)

    assert {:ok, %Record{id: id, namespace: "agent:redis-agent"}} =
             Redis.remember(agent, %{class: :semantic, kind: :fact, text: "remember me"}, target_opts)

    assert {:ok, %Record{id: ^id}} = Redis.get(agent, id, target_opts)

    query = Query.new!(%{text_contains: "remember"})

    assert {:ok,
            %RetrieveResult{
              scope: %Scope{provider: Redis, provider_key: :redis},
              provider: %ProviderInfo{provider: Redis, key: :redis},
              hits: [%{record: %Record{id: ^id}}]
            }} = Redis.retrieve(agent, query, target_opts)

    assert {:ok, true} = Redis.forget(agent, id, target_opts)
    assert {:ok, false} = Redis.forget(agent, id, target_opts)
    assert {:error, :not_found} = Redis.get(agent, id, target_opts)
  end

  test "ingest explain and consolidate return redis-tagged canonical structs", %{provider_opts: provider_opts} do
    expired_time = System.system_time(:millisecond) - 1_000

    assert {:ok, %Record{}} =
             Redis.remember(
               %{id: "redis-ingest"},
               %{
                 class: :episodic,
                 kind: :event,
                 text: "expired",
                 expires_at: expired_time
               },
               provider_opts
             )

    request =
      IngestRequest.new!(%{
        records: [
          %{class: :semantic, kind: :fact, text: "scope injected"}
        ],
        scope: %{namespace: "agent:redis-ingested"}
      })

    assert {:ok, %IngestResult{provider: %ProviderInfo{key: :redis, provider: Redis}} = ingest_result} =
             Redis.ingest(%{}, request, provider_opts)

    assert [%Record{namespace: "agent:redis-ingested"}] = ingest_result.records

    assert {:ok, %Explanation{summary: summary, provider: %ProviderInfo{key: :redis}}} =
             Redis.explain_retrieval(
               %{id: "redis-explain"},
               %{namespace: "agent:redis-ingested", text_contains: "scope"},
               provider_opts
             )

    assert summary =~ "redis provider"

    assert {:ok, %ConsolidationResult{provider: %ProviderInfo{key: :redis}, status: :ok}} =
             Redis.consolidate(%{id: "redis-ingest"}, provider_opts)
  end

  test "provider integrates with runtime via the :redis alias and top-level store opts", %{provider_opts: provider_opts} do
    runtime_store_opts = Keyword.fetch!(provider_opts, :store_opts)

    assert {:ok, %Record{namespace: "agent:runtime-redis"}} =
             Runtime.remember(
               %{id: "runtime-redis"},
               %{class: :semantic, kind: :fact, text: "runtime redis"},
               provider: :redis,
               store_opts: runtime_store_opts
             )

    assert {:ok, %ProviderInfo{key: :redis, provider: Redis}} =
             Runtime.info(%{}, provider: :redis, store_opts: runtime_store_opts)
  end
end
