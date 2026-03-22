defmodule Jido.Memory.Mem0Phase01IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Plugin
  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Provider.Mem0
  alias Jido.Memory.Provider.Tiered
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime

  test "mem0 passes the canonical provider contract through alias and module selection" do
    provider_opts = [
      store: ProviderFixtures.unique_store("phase01_mem0_contract"),
      namespace: "agent:phase01-mem0-contract",
      scoped_identity: [app: "cfg-app"]
    ]

    target = %{id: "phase01-mem0-contract-agent"}

    assert {:ok,
            %{
              record: %Record{id: record_id, metadata: metadata},
              fetched: %Record{id: fetched_id},
              records: [%Record{id: retrieved_id}],
              deleted?: true
            }} =
             ProviderContract.exercise_core_flow(
               :mem0,
               target,
               %{class: :semantic, kind: :fact, text: "phase01 mem0 contract flow"},
               %{text_contains: "phase01 mem0 contract flow", classes: [:semantic]},
               provider_opts: provider_opts,
               user_id: "runtime-user"
             )

    assert fetched_id == record_id
    assert retrieved_id == record_id

    assert get_in(metadata, ["mem0", "scope"]) == %{
             "user_id" => "runtime-user",
             "agent_id" => "phase01-mem0-contract-agent",
             "app_id" => "cfg-app"
           }

    assert {:ok, %{provider: Mem0, provider_style: :mem0}} =
             Runtime.info(
               target,
               [:provider, :provider_style],
               provider: Mem0,
               provider_opts: provider_opts
             )
  end

  test "mem0 plugin flows preserve scope metadata and runtime retrieval compatibility" do
    provider_opts = [
      store: ProviderFixtures.unique_store("phase01_mem0_plugin"),
      namespace: "agent:phase01-mem0-plugin",
      scoped_identity: [run: "cfg-run"]
    ]

    assert {:ok, plugin_state} =
             Plugin.mount(%{id: "phase01-mem0-plugin-agent"}, %{provider: :mem0, provider_opts: provider_opts})

    agent = %{id: "phase01-mem0-plugin-agent", app_id: "target-app", state: %{__memory__: plugin_state}}

    assert {:ok, %Record{id: id, metadata: metadata}} =
             Runtime.remember(
               agent,
               %{class: :semantic, kind: :fact, text: "phase01 mem0 plugin flow"},
               user_id: "plugin-user"
             )

    assert get_in(metadata, ["mem0", "scope"]) == %{
             "user_id" => "plugin-user",
             "agent_id" => "phase01-mem0-plugin-agent",
             "app_id" => "target-app",
             "run_id" => "cfg-run"
           }

    assert {:ok, [%Record{id: ^id}]} =
             Runtime.retrieve(agent, %{text_contains: "phase01 mem0 plugin flow"}, user_id: "plugin-user")

    assert {:ok, %{provider: Mem0, scoped_identity: %{enabled: true}}} =
             Runtime.info(agent, [:provider, :scoped_identity], [])
  end

  test "mem0 keeps canonical namespace isolation alongside scoped identity metadata" do
    store = ProviderFixtures.unique_store("phase01_mem0_namespaces")
    target = %{id: "phase01-mem0-namespaces-agent"}

    common_opts = [
      provider: :mem0,
      provider_opts: [store: store, scoped_identity: [user: "cfg-user"]]
    ]

    assert {:ok, %Record{id: alpha_id, metadata: alpha_metadata}} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "phase01 namespace alpha"},
               Keyword.merge(common_opts, namespace: "agent:phase01-alpha", user_id: "scope-user")
             )

    assert {:ok, %Record{id: beta_id}} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "phase01 namespace beta"},
               Keyword.merge(common_opts, namespace: "agent:phase01-beta", user_id: "scope-user")
             )

    assert get_in(alpha_metadata, ["mem0", "scope", "user_id"]) == "scope-user"

    assert {:ok, [%Record{id: ^alpha_id}]} =
             Runtime.retrieve(
               target,
               %{text_contains: "phase01 namespace"},
               Keyword.merge(common_opts, namespace: "agent:phase01-alpha", user_id: "scope-user")
             )

    assert {:ok, [%Record{id: ^beta_id}]} =
             Runtime.retrieve(
               target,
               %{text_contains: "phase01 namespace"},
               Keyword.merge(common_opts, namespace: "agent:phase01-beta", user_id: "scope-user")
             )
  end

  test "existing built-in providers remain unaffected by mem0 scope handling" do
    cases = [
      {"basic", ProviderFixtures.basic_provider("phase01_mem0_basic"), Basic},
      {"tiered", ProviderFixtures.tiered_provider("phase01_mem0_tiered"), Tiered}
    ]

    Enum.each(cases, fn {suffix, provider, expected_provider} ->
      target = %{id: "phase01-unaffected-#{suffix}"}
      text = "phase01 unaffected #{suffix}"

      assert {:ok, %Record{id: id, metadata: metadata}} =
               Runtime.remember(
                 target,
                 %{class: :semantic, kind: :fact, text: text},
                 provider: provider
               )

      assert {:ok, [%Record{id: ^id}]} =
               Runtime.retrieve(target, %{text_contains: text, classes: [:semantic]}, provider: provider)

      refute Map.has_key?(metadata, "mem0")
      assert {:ok, %{provider: ^expected_provider}} = Runtime.info(target, [:provider], provider: provider)
    end)
  end
end
