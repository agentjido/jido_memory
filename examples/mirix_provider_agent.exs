defmodule Example.MirixProviderAgent do
  alias Jido.Memory.Provider.Mirix
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store.ETS

  def plugin_config(prefix \\ "example_mirix") do
    %{provider: :mirix, provider_opts: provider_opts(prefix)}
  end

  def provider(prefix \\ "example_mirix") do
    {Mirix, provider_opts(prefix)}
  end

  def run_demo(agent_id \\ "mirix-agent-1", prefix \\ "example_mirix") do
    provider = provider(prefix)
    agent = %{id: agent_id}

    {:ok, remembered_record} =
      Runtime.remember(
        agent,
        %{class: :semantic, kind: :fact, text: "MIRIX providers support typed routed retrieval."},
        provider: provider
      )

    {:ok, ingest_result} =
      Mirix.ingest(
        agent,
        %{
          entries: [
            %{modality: :document, content: "Architecture notes for the MIRIX provider"},
            %{modality: :workflow, content: "workflow for release readiness"}
          ]
        },
        provider: provider
      )

    {:ok, retrieved_records} =
      Runtime.retrieve(
        agent,
        %{
          text_contains: "MIRIX",
          query_extensions: %{mirix: %{memory_types: [:semantic, :resource], planner_mode: :focused}}
        },
        provider: provider
      )

    {:ok, explanation} =
      Runtime.explain_retrieval(
        agent,
        %{
          text_contains: "workflow",
          query_extensions: %{mirix: %{planner_mode: :focused}}
        },
        provider: provider
      )

    {:ok, vault_record} =
      Mirix.put_vault_entry(
        agent,
        %{kind: :credential, text: "mirix-secret-token"},
        provider: provider
      )

    {:ok, direct_vault_record} = Mirix.get_vault_entry(agent, vault_record.id, provider: provider)

    {:ok,
     %{
       provider: provider,
       remembered_record: remembered_record,
       ingest_result: ingest_result,
       retrieved_records: retrieved_records,
       explanation: explanation,
       vault_record: vault_record,
       direct_vault_record: direct_vault_record
     }}
  end

  defp provider_opts(prefix) do
    [
      core_store: store(prefix, "core"),
      episodic_store: store(prefix, "episodic"),
      semantic_store: store(prefix, "semantic"),
      procedural_store: store(prefix, "procedural"),
      resource_store: store(prefix, "resource"),
      vault_store: store(prefix, "vault"),
      retrieval: [planner_mode: :broad]
    ]
  end

  defp store(prefix, suffix) do
    table = String.to_atom("#{prefix}_#{suffix}")
    {ETS, [table: table]}
  end
end
