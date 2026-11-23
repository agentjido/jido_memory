defmodule Jido.Memory.RecallForModelTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Plugin.Preparation
  alias Jido.AI.Context
  alias Jido.Joi
  alias Jido.Memory.Actions.{RecallForModel, RecallGranted}
  alias Jido.Memory.Plugin
  alias Jido.Memory.Store.ETS
  alias SupportDesk.{MemoryAgent, MemoryFixture}

  @compile {:no_warn_undefined, MemoryAgent}

  setup_all do
    Code.require_file("../../examples/00_start_here/00_02_answer_from_memory/agent.exs", __DIR__)
    :ok
  end

  setup do
    agent = MemoryAgent.instantiate!(id: "support-test")
    value = %{issue: "duplicate_charge", summary: "Refunded the second charge", internal_note: "Ledger follow-up"}

    older = MemoryAgent.resolve_signal!(%{key: "T-16", value: value})
    resolution = MemoryAgent.resolve_signal!(%{key: "T-17", value: value})
    {:ok, agent, [_]} = MemoryAgent.cmd(agent, older)
    {:ok, agent, [_]} = MemoryAgent.cmd(agent, resolution)
    %{agent: agent, resolution: resolution}
  end

  test "the question Flow receives a bounded and projected read", %{agent: agent, resolution: resolution} do
    data = ask(agent, %{issue: "duplicate_charge"})
    source_id = resolution.id
    summary = "Refunded the second charge"

    assert data.output == "[T-17] #{summary}"

    assert %{
             decision: :allowed,
             records: [%{key: "T-17", source_signal_id: ^source_id, value: %{summary: ^summary} = value}]
           } =
             data.memory_trace.recall

    assert value == %{summary: summary}

    assert %{role: :user, content: "Memory evidence (retrieved records):\n" <> json} =
             List.last(data.memory_trace.model_input)

    assert Jason.decode!(json) == [%{"key" => "T-17", "value" => %{"summary" => summary}}]
  end

  test "the question Flow rejects an unapproved filter", %{agent: agent} do
    data = ask(agent, %{internal_note: "Ledger follow-up"})
    assert %{decision: :filter_denied, records: []} = data.memory_trace.recall
    assert [%{role: :system}, %{role: :user}] = data.memory_trace.model_input
  end

  test "keeps valid native values available when they cannot be encoded as model evidence" do
    schema = Joi.object(%{location: Joi.tuple({Joi.integer(), Joi.integer()})})
    record = %{key: "T-17", value: %{location: {1, 2}}, source_signal_id: "resolved"}
    {prompt, context} = evidence_context(schema, :location, [record])

    assert {:ok, %{context: ^prompt, recall: recall}} = recall_for_model(prompt, context)
    assert recall.records == [record]
    assert recall.omitted == [%{key: "T-17", reason: :not_json_encodable}]

    assert {:ok, %{recall: %{decision: :allowed, records: [^record]}}} =
             Jido.Exec.run(RecallGranted, %{grant: :evidence}, context)
  end

  test "budgets the full evidence message and uses smaller records that fit" do
    schema = Joi.object(%{summary: Joi.string()})
    large = %{key: "T-17", value: %{summary: String.duplicate("a", 8_000)}, source_signal_id: "large"}
    small = %{key: "T-18", value: %{summary: "ok"}, source_signal_id: "small"}
    {prompt, context} = evidence_context(schema, :summary, [large, small])

    assert {:ok, %{context: updated, recall: recall}} = recall_for_model(prompt, context, %{max_evidence_bytes: 100})
    assert recall.records == [large, small]
    assert recall.omitted == [%{key: "T-17", reason: :evidence_budget}]
    assert [%{content: [%{text: text}]} | _] = Enum.reverse(updated.request.context.messages)
    assert byte_size(text) <= 100
    assert "Memory evidence (retrieved records):\n" <> json = text
    assert Jason.decode!(json) == [%{"key" => "T-18", "value" => %{"summary" => "ok"}}]

    assert {:ok, %{context: ^prompt, recall: %{omitted: [%{}, %{}]}}} =
             recall_for_model(prompt, context, %{max_evidence_bytes: 1})

    assert {:ok, %{recall: %{omitted: [%{key: "T-17", reason: :evidence_budget}]}}} =
             recall_for_model(prompt, context)
  end

  test "preparation for another root Flow supplies no grant", %{agent: agent, resolution: resolution} do
    config = Enum.find_value(agent.plugins, fn plugin -> if plugin.provider == Plugin, do: plugin.data end)

    preparation = %Preparation{
      plugin: Plugin,
      agent_id: agent.id,
      agent_module: MemoryAgent,
      agent_state: agent.state,
      signal: resolution,
      plugin_state: agent.state.memory,
      route_candidates: [%{handler: %{kind: :flow, target: Jido.AI.Reasoning.ChainOfThought}}]
    }

    assert {:ok, prepared} = Plugin.prepare(preparation, Map.to_list(config))
    assert {:ok, prompt} = Context.new(ReqLLM.Context.new([ReqLLM.Context.user("Question")]))
    params = %{grant: :prior_resolutions, context: prompt}

    assert {:ok, %{context: ^prompt, recall: %{decision: :grant_unavailable, records: []}}} =
             Jido.Exec.run(RecallForModel, params, %{
               agent_state: agent.state,
               plugin_inputs: %{Plugin => %Jido.Plugin.Input{prepared: prepared}}
             })
  end

  test "a granted store outage gives the reasoning Flow an empty recall" do
    schema = Joi.object(%{summary: Joi.string()})
    {prompt, context} = evidence_context(schema, :summary, [])
    binding = {ETS, %{name: __MODULE__.OfflineOwner, scope: "support"}}

    context =
      context
      |> put_in([:plugin_inputs, Plugin, Access.key(:runtime)], :live)
      |> update_in([:plugin_inputs, Plugin, Access.key(:prepared), :collections, :notes], &Map.put(&1, :store, binding))

    assert {:ok, %{context: ^prompt, recall: %{decision: :store_unavailable, records: []}}} =
             recall_for_model(prompt, context)
  end

  defp ask(agent, where) do
    request =
      MemoryAgent.request_signal!(%{
        input: "How did we resolve the last duplicate charge?",
        model: "fixture:repeat-ticket",
        where: where
      })

    assert {:ok, _agent, [%{signal: reply}]} =
             MemoryAgent.cmd(agent, request, context: %{jido_ai_inference_client: MemoryFixture})

    reply.data
  end

  defp recall_for_model(prompt, context, opts \\ %{}) do
    Jido.Exec.run(RecallForModel, Map.merge(%{context: prompt, grant: :evidence}, opts), context)
  end

  defp evidence_context(schema, expose, records) do
    prepared = %{
      collections: %{notes: %{schema: schema}},
      reads: %{evidence: %{collection: :notes, filters: [], expose: [expose], limit: 10}}
    }

    {:ok, prompt} = Context.new(ReqLLM.Context.new([ReqLLM.Context.user("Question")]))

    {prompt,
     %{
       agent_state: %{memory: %{notes: records}},
       plugin_inputs: %{Plugin => %Jido.Plugin.Input{prepared: prepared}}
     }}
  end
end
