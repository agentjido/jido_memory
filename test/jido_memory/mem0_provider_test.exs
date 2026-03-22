defmodule Jido.Memory.Mem0ProviderTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Plugin
  alias Jido.Memory.Provider.Mem0
  alias Jido.Memory.ProviderContract
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime
  alias Jido.Signal

  test "mem0 exposes ingestion capability metadata and extraction context settings" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase02_meta"),
         namespace: "agent:mem0-phase02-meta",
         extraction: [recent_window: 2, summary_context: :required]
       ]}

    target = %{id: "mem0-phase02-meta-agent"}

    assert {:ok, capabilities} = Runtime.capabilities(target, provider: provider)
    assert capabilities.ingestion.batch == true
    assert capabilities.ingestion.routed == true
    assert capabilities.ingestion.access == :provider_direct

    assert {:ok, %{provider: Mem0, extraction_context: extraction_context}} =
             Runtime.info(target, [:provider, :extraction_context, :topology], provider: provider)

    assert extraction_context.recent_window == 2
    assert extraction_context.summary_context == :required
    assert extraction_context.summary_generation == :provider_owned
    assert extraction_context.supported_payloads == [:messages, :entries]
  end

  test "mem0 ingest extracts scoped candidates from message batches with recency and summary context" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase02_messages"),
         namespace: "agent:mem0-phase02-messages",
         extraction: [recent_window: 2, summary_context: :optional]
       ]}

    target = %{id: "mem0-phase02-message-agent", app_id: "phase02-app"}

    payload = %{
      summary: "The user shared stable personal preferences.",
      messages: [
        %{role: :user, content: "My favorite language is Elixir."},
        %{role: :assistant, content: "Noted."},
        %{role: :user, content: "I live in Denver."}
      ]
    }

    assert {:ok, summary} = Mem0.ingest(target, payload, provider: provider, user_id: "user-1")

    assert summary.provider == Mem0
    assert summary.extraction_context.recent_window == 2
    assert summary.extraction_context.summary_present == true

    assert summary.extracted_candidates == [
             %{
               action: :upsert,
               fact_key: "location:home",
               fact_value: "denver",
               text: "location:home=denver"
             }
           ]

    assert [%{reason: :unsupported_role} | _] = summary.skipped_candidates
    assert length(summary.created_ids) == 1
    assert summary.updated_ids == []
    assert summary.deleted_ids == []
    assert summary.noop_ids == []
    assert summary.maintenance.add == 1

    assert summary.maintenance_results == [
             %{fact_key: "location:home", outcome: :add, record_id: hd(summary.created_ids)}
           ]

    assert {:ok, [%Record{id: id, metadata: metadata}]} =
             Runtime.retrieve(
               target,
               %{text_contains: "location:home=denver", classes: [:semantic]},
               provider: provider,
               user_id: "user-1"
             )

    assert id in summary.created_ids

    assert get_in(metadata, ["mem0", "scope"]) == %{
             "user_id" => "user-1",
             "agent_id" => "mem0-phase02-message-agent",
             "app_id" => "phase02-app"
           }

    assert get_in(metadata, ["mem0", "write_mode"]) == :ingest
    assert get_in(metadata, ["mem0", "fact_key"]) == "location:home"
  end

  test "mem0 ingest accepts interaction entries payloads and enforces required summaries" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase02_entries"),
         namespace: "agent:mem0-phase02-entries",
         extraction: [recent_window: 4, summary_context: :required]
       ]}

    target = %{id: "mem0-phase02-entry-agent"}

    assert {:error, :missing_summary_context} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "I use Neovim for editing."}]},
               provider: provider
             )

    assert {:ok, summary} =
             Mem0.ingest(
               target,
               %{
                 summary: "The user described stable tooling preferences.",
                 entries: [%{role: :user, content: "I use Neovim for editing."}]
               },
               provider: provider,
               user_id: "user-entries"
             )

    assert summary.extracted_candidates == [
             %{
               action: :upsert,
               fact_key: "tool:editing",
               fact_value: "neovim",
               text: "tool:editing=neovim"
             }
           ]
  end

  test "mem0 reconciliation returns add, noop, update, and delete outcomes deterministically" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase02_reconcile"),
         namespace: "agent:mem0-phase02-reconcile",
         extraction: [recent_window: 4, summary_context: :optional]
       ]}

    target = %{id: "mem0-phase02-reconcile-agent"}

    assert {:ok, add_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Elixir."}]},
               provider: provider,
               user_id: "user-reconcile"
             )

    [record_id] = add_summary.created_ids
    assert add_summary.maintenance.add == 1

    assert {:ok, noop_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Elixir."}]},
               provider: provider,
               user_id: "user-reconcile"
             )

    assert noop_summary.created_ids == []
    assert noop_summary.noop_ids == [record_id]
    assert noop_summary.maintenance.noop == 1

    assert {:ok, update_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Erlang."}]},
               provider: provider,
               user_id: "user-reconcile"
             )

    assert update_summary.updated_ids == [record_id]
    assert update_summary.maintenance.update == 1

    assert update_summary.maintenance_results == [
             %{
               fact_key: "favorite:language",
               outcome: :update,
               previous_record_id: record_id,
               record_id: record_id
             }
           ]

    assert {:ok, [%Record{id: ^record_id, text: "favorite:language=erlang", metadata: metadata}]} =
             Runtime.retrieve(
               target,
               %{text_contains: "favorite:language=", classes: [:semantic]},
               provider: provider,
               user_id: "user-reconcile"
             )

    assert get_in(metadata, ["mem0", "maintenance_action"]) == :update
    assert get_in(metadata, ["mem0", "previous_fact_value"]) == "elixir"

    assert {:ok, delete_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "Forget that my favorite language is Erlang."}]},
               provider: provider,
               user_id: "user-reconcile"
             )

    assert delete_summary.deleted_ids == [record_id]
    assert delete_summary.maintenance.delete == 1

    assert {:ok, []} =
             Runtime.retrieve(
               target,
               %{text_contains: "favorite:language=", classes: [:semantic]},
               provider: provider,
               user_id: "user-reconcile"
             )
  end

  test "mem0 direct remember stays canonical and is distinguished from ingestion writes" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase02_direct"),
         namespace: "agent:mem0-phase02-direct"
       ]}

    target = %{id: "mem0-phase02-direct-agent"}

    assert {:ok, %Record{id: id, metadata: metadata}} =
             Runtime.remember(
               target,
               %{class: :semantic, kind: :fact, text: "direct mem0 write"},
               provider: provider,
               user_id: "user-direct"
             )

    assert get_in(metadata, ["mem0", "write_mode"]) == :direct
    assert get_in(metadata, ["mem0", "scope", "user_id"]) == "user-direct"

    assert {:ok, [%Record{id: ^id}]} =
             Runtime.retrieve(
               target,
               %{text_contains: "direct mem0 write", classes: [:semantic]},
               provider: provider,
               user_id: "user-direct"
             )
  end

  test "mem0 plugin auto-capture remains on the canonical remember path" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase02_plugin"),
         namespace: "agent:mem0-phase02-plugin"
       ]}

    assert {:ok, plugin_state} =
             Plugin.mount(%{id: "mem0-phase02-plugin-agent"}, %{provider: provider})

    agent = %{id: "mem0-phase02-plugin-agent", state: %{__memory__: plugin_state}}
    context = %{agent: agent}
    signal = Signal.new!("ai.react.query", %{query: "Where do I live?"}, source: "/ai")

    assert {:ok, :continue} = Plugin.handle_signal(signal, context)

    assert {:ok, [%Record{kind: :user_query, metadata: metadata}]} =
             Runtime.retrieve(agent, %{classes: [:episodic], kinds: [:user_query]}, [])

    assert get_in(metadata, ["mem0", "write_mode"]) == :direct
    assert get_in(metadata, ["mem0", "fact_key"]) == nil
    assert Map.has_key?(metadata, :signal_id) or Map.has_key?(metadata, "signal_id")
  end

  test "mem0 retrieval honors scope query extensions and retrieval mode hints" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase03_scope"),
         namespace: "agent:mem0-phase03-scope",
         retrieval: [mode: :balanced]
       ]}

    target = %{id: "mem0-phase03-scope-agent"}

    assert {:ok, _summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Elixir."}]},
               provider: provider,
               user_id: "user-a"
             )

    assert {:ok, first_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "I live in Denver."}]},
               provider: provider,
               user_id: "user-b"
             )

    assert {:ok, second_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Erlang."}]},
               provider: provider,
               user_id: "user-b"
             )

    [location_id] = first_summary.created_ids
    [favorite_id] = second_summary.created_ids

    assert {:ok, [%Record{id: ^favorite_id}, %Record{id: ^location_id}]} =
             Runtime.retrieve(
               target,
               %{
                 classes: [:semantic],
                 query_extensions: %{
                   mem0: %{
                     scope: %{user_id: "user-b"},
                     retrieval_mode: :fact_key_first,
                     fact_key: "favorite:language"
                   }
                 }
               },
               provider: provider
             )
  end

  test "mem0 recall and retrieve stay aligned for the overlapping shared query subset" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase03_recall"),
         namespace: "agent:mem0-phase03-recall"
       ]}

    assert {:ok, plugin_state} =
             Plugin.mount(%{id: "mem0-phase03-recall-agent", user_id: "recall-user"}, %{provider: provider})

    agent = %{id: "mem0-phase03-recall-agent", user_id: "recall-user", state: %{__memory__: plugin_state}}

    assert {:ok, %Record{id: recent_id}} =
             Runtime.remember(
               agent,
               %{class: :semantic, kind: :fact, text: "phase03 direct recent"},
               now: 2_000
             )

    assert {:ok, %Record{id: older_id}} =
             Runtime.remember(
               agent,
               %{class: :semantic, kind: :fact, text: "phase03 direct older"},
               now: 1_000
             )

    query = %{
      classes: [:semantic],
      query_extensions: %{mem0: %{retrieval_mode: :recent_first}}
    }

    assert {:ok, [%Record{id: ^recent_id}, %Record{id: ^older_id}]} =
             Runtime.retrieve(agent, query, [])

    assert {:ok, [%Record{id: ^recent_id}, %Record{id: ^older_id}]} =
             Runtime.recall(agent, query)
  end

  test "mem0 explain_retrieval returns the canonical envelope with additive retrieval context" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase03_explain"),
         namespace: "agent:mem0-phase03-explain",
         retrieval: [mode: :fact_key_first]
       ]}

    target = %{id: "mem0-phase03-explain-agent"}

    assert {:ok, _summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Elixir."}]},
               provider: provider,
               user_id: "user-explain"
             )

    query = %{
      classes: [:semantic],
      query_extensions: %{mem0: %{scope: %{user_id: "user-explain"}, fact_key: "favorite:language"}}
    }

    assert {:ok, explanation} = Runtime.explain_retrieval(target, query, provider: provider)
    assert ProviderContract.canonical_explanation?(explanation)
    assert explanation.provider == Mem0
    assert explanation.result_count == 1
    assert explanation.query.extensions.mem0.fact_key == "favorite:language"
    assert explanation.extensions.mem0.scope.effective.user_id == "user-explain"
    assert explanation.extensions.mem0.retrieval_strategy.mode == :fact_key_first

    assert explanation.extensions.mem0.reconciliation.ranking_signals == [
             :retrieval_mode,
             :maintenance_action,
             :recency
           ]

    assert hd(explanation.results).matched_on == [:class, :fact_key]
    assert hd(explanation.results).ranking_context.fact_key_match == true
  end

  test "mem0 graph augmentation enriches explanation output without replacing canonical records" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase03_graph"),
         namespace: "agent:mem0-phase03-graph",
         retrieval: [graph_augmentation: [enabled: true, relationship_limit: 3]]
       ]}

    target = %{id: "mem0-phase03-graph-agent"}

    assert {:ok, summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Elixir."}]},
               provider: provider,
               user_id: "user-graph"
             )

    [record_id] = summary.created_ids

    query = %{
      classes: [:semantic],
      query_extensions: %{
        mem0: %{scope: %{user_id: "user-graph"}, graph: %{enabled: true, entity_focus: ["favorite:language"]}}
      }
    }

    assert {:ok, [%Record{id: ^record_id}]} = Runtime.retrieve(target, query, provider: provider)
    assert {:ok, explanation} = Runtime.explain_retrieval(target, query, provider: provider)

    assert explanation.result_count == 1
    assert explanation.extensions.mem0.graph.enabled == true
    assert explanation.extensions.mem0.graph.source == :query_extension
    assert explanation.extensions.mem0.graph.entity_focus == ["favorite:language"]
    assert explanation.extensions.mem0.graph.entity_count >= 1
    assert explanation.extensions.mem0.graph.relationship_count == 1
    assert Enum.any?(explanation.extensions.mem0.graph.entities, &(&1.type == :fact_key))
    assert hd(explanation.extensions.mem0.graph.relationships).predicate == :value
  end

  test "mem0 graph augmentation can be disabled cleanly" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase03_graph_disabled"),
         namespace: "agent:mem0-phase03-graph-disabled"
       ]}

    target = %{id: "mem0-phase03-graph-disabled-agent"}

    assert {:ok, _summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "I live in Denver."}]},
               provider: provider,
               user_id: "user-graph-disabled"
             )

    query = %{
      classes: [:semantic],
      query_extensions: %{mem0: %{scope: %{user_id: "user-graph-disabled"}}}
    }

    assert {:ok, explanation} = Runtime.explain_retrieval(target, query, provider: provider)
    assert explanation.extensions.mem0.graph.enabled == false
    assert explanation.extensions.mem0.graph.relationships == []
  end

  test "mem0 feedback updates scoped record metadata and records provider-direct history" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase04_feedback"),
         namespace: "agent:mem0-phase04-feedback"
       ]}

    target = %{id: "mem0-phase04-feedback-agent"}

    assert {:ok, summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "I live in Denver."}]},
               provider: provider,
               user_id: "feedback-user",
               now: 100
             )

    [record_id] = summary.created_ids

    assert {:ok, feedback} =
             Mem0.feedback(
               target,
               record_id,
               %{status: :useful, note: "keep this fact"},
               provider: provider,
               user_id: "feedback-user",
               now: 200
             )

    assert feedback.record_id == record_id
    assert feedback.feedback.status == :useful
    assert feedback.feedback.count == 1

    assert {:ok, %Record{metadata: metadata}} =
             Runtime.get(target, record_id, provider: provider, user_id: "feedback-user")

    assert get_in(metadata, ["mem0", "feedback", "status"]) == :useful
    assert get_in(metadata, ["mem0", "feedback", "note"]) == "keep this fact"

    assert {:ok, history} =
             Mem0.history(
               target,
               provider: provider,
               user_id: "feedback-user",
               record_id: record_id
             )

    assert Enum.map(history.events, & &1.event_type) == [:feedback, :ingest_add]
    assert hd(history.events).details[:note] == "keep this fact"
  end

  test "mem0 history filters reconciliation events deterministically" do
    provider =
      {:mem0,
       [
         store: ProviderFixtures.unique_store("mem0_phase04_history"),
         namespace: "agent:mem0-phase04-history"
       ]}

    target = %{id: "mem0-phase04-history-agent"}

    assert {:ok, add_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Elixir."}]},
               provider: provider,
               user_id: "history-user",
               now: 100
             )

    [record_id] = add_summary.created_ids

    assert {:ok, _noop_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Elixir."}]},
               provider: provider,
               user_id: "history-user",
               now: 200
             )

    assert {:ok, _update_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "My favorite language is Erlang."}]},
               provider: provider,
               user_id: "history-user",
               now: 300
             )

    assert {:ok, _delete_summary} =
             Mem0.ingest(
               target,
               %{entries: [%{role: :user, content: "Forget that my favorite language is Erlang."}]},
               provider: provider,
               user_id: "history-user",
               now: 400
             )

    assert {:ok, history} =
             Mem0.history(
               target,
               provider: provider,
               user_id: "history-user",
               fact_key: "favorite:language"
             )

    assert Enum.map(history.events, & &1.event_type) == [:ingest_delete, :ingest_update, :ingest_noop, :ingest_add]
    assert Enum.all?(history.events, &(&1.record_id == record_id or &1.event_type == :ingest_delete))

    assert {:ok, filtered_history} =
             Mem0.history(
               target,
               provider: provider,
               user_id: "history-user",
               record_id: record_id,
               event_types: [:ingest_update, :ingest_noop]
             )

    assert Enum.map(filtered_history.events, & &1.event_type) == [:ingest_update, :ingest_noop]
  end
end
