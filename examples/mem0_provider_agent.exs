defmodule Example.Mem0ProviderAgent do
  alias Jido.Memory.Provider.Mem0
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store.ETS

  def plugin_config(prefix \\ "example_mem0") do
    %{provider: :mem0, provider_opts: provider_opts(prefix)}
  end

  def provider(prefix \\ "example_mem0") do
    {Mem0, provider_opts(prefix)}
  end

  def run_demo(agent_id \\ "mem0-agent-1", prefix \\ "example_mem0") do
    provider = provider(prefix)
    agent = %{id: agent_id, app_id: "example-app"}

    {:ok, remembered_record} =
      Runtime.remember(
        agent,
        %{class: :semantic, kind: :fact, text: "My favorite language is Elixir."},
        provider: provider,
        user_id: "demo-user"
      )

    {:ok, ingest_result} =
      Mem0.ingest(
        agent,
        %{
          entries: [
            %{role: :user, content: "I live in Denver."},
            %{role: :assistant, content: "I'll remember that you live in Denver."}
          ]
        },
        provider: provider,
        user_id: "demo-user",
        now: 100
      )

    [ingested_id | _] = ingest_result.created_ids

    {:ok, retrieved_records} =
      Runtime.retrieve(
        agent,
        %{
          text_contains: "Denver",
          query_extensions: %{mem0: %{scope: %{user_id: "demo-user"}, retrieval_mode: :fact_key_first}}
        },
        provider: provider
      )

    {:ok, explanation} =
      Runtime.explain_retrieval(
        agent,
        %{
          text_contains: "favorite language",
          query_extensions: %{mem0: %{scope: %{user_id: "demo-user"}, fact_key: "favorite:language"}}
        },
        provider: provider
      )

    {:ok, feedback_result} =
      Mem0.feedback(
        agent,
        ingested_id,
        %{status: :useful, note: "Keep this stable user profile fact."},
        provider: provider,
        user_id: "demo-user",
        now: 200
      )

    {:ok, history_result} =
      Mem0.history(
        agent,
        provider: provider,
        user_id: "demo-user",
        record_id: ingested_id
      )

    {:ok, export_result} =
      Mem0.export(
        agent,
        provider: provider,
        user_id: "demo-user",
        include_history: true
      )

    {:ok,
     %{
       provider: provider,
       remembered_record: remembered_record,
       ingest_result: ingest_result,
       retrieved_records: retrieved_records,
       explanation: explanation,
       feedback_result: feedback_result,
       history_result: history_result,
       export_result: export_result
     }}
  end

  defp provider_opts(prefix) do
    [
      store: store(prefix),
      namespace: "agent:#{prefix}",
      scoped_identity: [allow: [:user_id, :agent_id, :app_id, :run_id]],
      retrieval: [mode: :balanced, graph_augmentation: [enabled: true, include_relationships: true]]
    ]
  end

  defp store(prefix) do
    table = String.to_atom("#{prefix}_store")
    {ETS, [table: table]}
  end
end
