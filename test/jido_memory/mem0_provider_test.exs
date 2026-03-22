defmodule Jido.Memory.Mem0ProviderTest do
  use ExUnit.Case, async: true

  alias Jido.Memory.Provider.Mem0
  alias Jido.Memory.ProviderFixtures
  alias Jido.Memory.Record
  alias Jido.Memory.Runtime

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
             Runtime.info(target, [:provider, :extraction_context], provider: provider)

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
end
