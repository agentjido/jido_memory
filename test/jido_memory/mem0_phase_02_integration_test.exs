defmodule Jido.Memory.Mem0Phase02IntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Plugin
  alias Jido.Memory.Provider.Mem0
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime
  alias Jido.Signal

  test "mem0 ingestion extracts and reconciles stable facts through provider-direct maintenance" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase02_integration"),
         namespace: "agent:mem0-phase02-integration",
         extraction: [recent_window: 4, summary_context: :optional]
       ]}

    target = %{id: "mem0-phase02-integration-agent", app_id: "phase02-app"}

    assert {:ok, add_summary} =
             Mem0.ingest(
               target,
               %{
                 summary: "The user shared stable language preferences.",
                 messages: [
                   %{role: :user, content: "My favorite language is Elixir."},
                   %{role: :assistant, content: "I'll remember that."}
                 ]
               },
               provider: provider,
               user_id: "phase02-user"
             )

    [record_id] = add_summary.created_ids
    assert add_summary.maintenance.add == 1

    assert {:ok, update_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Erlang."}]},
               provider: provider,
               user_id: "phase02-user"
             )

    assert update_summary.updated_ids == [record_id]
    assert update_summary.maintenance.update == 1

    assert {:ok, [%Record{id: ^record_id, text: "favorite:language=erlang", metadata: metadata}]} =
             Runtime.retrieve(
               target,
               %{text_contains: "favorite:language=", classes: [:semantic]},
               provider: provider,
               user_id: "phase02-user"
             )

    assert get_in(metadata, ["mem0", "maintenance_action"]) == :update

    assert get_in(metadata, ["mem0", "scope"]) == %{
             "user_id" => "phase02-user",
             "agent_id" => "mem0-phase02-integration-agent",
             "app_id" => "phase02-app"
           }

    assert {:ok, delete_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "Forget that my favorite language is Erlang."}]},
               provider: provider,
               user_id: "phase02-user"
             )

    assert delete_summary.deleted_ids == [record_id]
    assert delete_summary.maintenance.delete == 1

    assert {:ok, []} =
             Runtime.retrieve(
               target,
               %{text_contains: "favorite:language=", classes: [:semantic]},
               provider: provider,
               user_id: "phase02-user"
             )
  end

  test "mem0 maintenance provenance stays additive inside provider metadata" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase02_provenance"),
         namespace: "agent:mem0-phase02-provenance"
       ]}

    target = %{id: "mem0-phase02-provenance-agent"}

    assert {:ok, _summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "I live in Denver."}]},
               provider: provider,
               user_id: "provenance-user"
             )

    assert {:ok, _summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "I live in Boulder."}]},
               provider: provider,
               user_id: "provenance-user"
             )

    assert {:ok, [%Record{metadata: metadata}]} =
             Runtime.retrieve(
               target,
               %{text_contains: "location:home=", classes: [:semantic]},
               provider: provider,
               user_id: "provenance-user"
             )

    assert Map.has_key?(metadata, "mem0")
    assert get_in(metadata, ["mem0", "previous_fact_value"]) == "denver"
    assert get_in(metadata, ["mem0", "similar_record_ids"]) |> is_list()
    refute Map.has_key?(metadata, "maintenance_action")
    refute Map.has_key?(metadata, "previous_fact_value")
  end

  test "canonical writes and plugin auto-capture remain on the shared remember path" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase02_plugin_flow"),
         namespace: "agent:mem0-phase02-plugin-flow"
       ]}

    target = %{id: "mem0-phase02-plugin-flow-agent"}

    assert {:ok, %Record{id: direct_id, metadata: direct_metadata}} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "phase02 direct canonical write"},
               provider: provider,
               user_id: "plugin-user"
             )

    assert get_in(direct_metadata, ["mem0", "write_mode"]) == :direct

    assert {:ok, plugin_state} =
             Plugin.mount(%{id: "mem0-phase02-plugin-agent"}, %{provider: provider})

    agent = %{id: "mem0-phase02-plugin-agent", state: %{__memory__: plugin_state}}
    signal = Signal.new!("ai.react.query", %{query: "What did I say?"}, source: "/ai")

    assert {:ok, :continue} = Plugin.handle_signal(signal, %{agent: agent})

    assert {:ok, [%Record{id: ^direct_id}]} =
             Runtime.retrieve(
               target,
               %{text_contains: "phase02 direct canonical write", classes: [:semantic]},
               provider: provider,
               user_id: "plugin-user"
             )

    assert {:ok, [%Record{kind: :user_query, metadata: plugin_metadata}]} =
             Runtime.retrieve(agent, %{classes: [:episodic], kinds: [:user_query]}, [])

    assert get_in(plugin_metadata, ["mem0", "write_mode"]) == :direct
    assert get_in(plugin_metadata, ["mem0", "fact_key"]) == nil
  end

  test "non-mem0 providers remain unaffected by mem0 maintenance capabilities" do
    assert ProviderContract.supports?(ProviderFixtures.basic_provider("mem0_phase02_basic"), [:ingestion, :batch]) ==
             false

    assert ProviderContract.supports?(ProviderFixtures.tiered_provider("mem0_phase02_tiered"), [:ingestion, :batch]) ==
             false

    basic_target = %{id: "mem0-phase02-basic-target"}
    basic_provider = ProviderFixtures.basic_provider("mem0_phase02_basic_runtime")

    assert {:ok, %Record{id: id}} =
             Runtime.remember(
               basic_target,
               %{class: :semantic, kind: :fact, text: "phase02 basic unaffected"},
               provider: basic_provider
             )

    assert {:ok, [%Record{id: ^id, metadata: metadata}]} =
             Runtime.retrieve(
               basic_target,
               %{text_contains: "phase02 basic unaffected", classes: [:semantic]},
               provider: basic_provider
             )

    refute Map.has_key?(metadata, "mem0")
  end
end
