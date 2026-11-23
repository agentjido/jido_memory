Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.RegressionFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "test_retrieval_regression",
    schema: Joi.object(%{question: Joi.string(), mode: Joi.enum([:off, :hybrid, :graph]), depth: Joi.integer()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "retrieve", [
      mode <- input(:mode),
      depth <- input(:depth),
      question <- input(:question),
      context <- context()
    ] do
      {:ok, %{retrieval: retrieve(mode, depth, question, context)}}
    end

    step "check_procedure", [result <- result("retrieve", :retrieval), mode <- input(:mode)],
      inline: [context: context] do
      {:ok, records} = Memory.recall(context, :procedures, where: %{release: "v1.0"})
      selected = if mode == :graph && Enum.any?(result.passages, &(&1.id == "G-REPAIR")), do: List.first(records)
      {:ok, %{record: selected}}
    end

    step "answer", [
      question <- input(:question),
      retrieval <- result("retrieve", :retrieval),
      procedure <- result("check_procedure", :record),
      inference <- context(:inference)
    ] do
      sources = retrieval.passages ++ procedure_evidence(procedure)
      evidence = Enum.map_join(sources, "\n", &"[#{&1.id}] #{&1.text}")

      {reply, call} =
        Inference.call!(inference, [
          Context.system(
            "Use only the evidence. If it lacks a repair, say No verified repair. Cite source IDs exactly."
          ),
          Context.user("Question: #{question}\nEvidence:\n#{evidence}")
        ])

      {:ok,
       %{
         trace: %{
           retrieval: retrieval,
           procedure: procedure,
           sent_ids: Enum.map(sources, & &1.id),
           call: call,
           response: reply,
           metrics: grade(reply, sources)
         }
       }}
    end

    output(result("answer"))
  end

  defp retrieve(:off, _depth, _question, _context), do: %{mode: :off, depth: nil, passages: []}

  defp retrieve(mode, depth, question, context) do
    query = %{package: "relay_kit", version: "v1.0", question: question}

    {:ok, %{evidence: hits}} =
      case mode do
        :hybrid ->
          Memory.access(context, :index, :guides, :search, Map.merge(query, %{mode: :hybrid, limit: 2, threshold: 0.5}))

        :graph ->
          Memory.access(context, :graph, :guide_links, :search, Map.put(query, :depth, depth))
      end

    passages =
      for hit <- hits,
          %{id: id, path: path} <- [identify(hit.citation["path"])] do
        %{id: id, path: path, chunk_id: hit.chunk_id, text: hit.text}
      end

    %{mode: mode, depth: if(mode == :graph, do: depth), passages: passages}
  end

  defp identify("guides/symptoms.md" = path), do: %{id: "G-SYMPTOM", path: path}
  defp identify("guides/repair.md" = path), do: %{id: "G-REPAIR", path: path}
  defp identify(_), do: nil

  defp procedure_evidence(nil), do: []
  defp procedure_evidence(record), do: [%{id: record.key, text: record.value.summary}]

  defp grade(text, sources) do
    text = text || ""
    allowed = Enum.map(sources, & &1.id)

    cited =
      Regex.scan(~r/[\[【]((?:G|PROC)-[A-Z0-9-]+)[\]】]/u, text, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()

    correct = Enum.count(cited, &(&1 in allowed))
    complete = Enum.all?(["G-REPAIR", "PROC-4"], &(&1 in allowed and &1 in cited))
    task_success = complete && Regex.match?(~r/select\W+prime/i, text)

    %{
      task_success: task_success,
      cited: cited,
      correct_citations: correct,
      citation_accuracy: if(cited == [], do: nil, else: correct / length(cited))
    }
  end
end

defmodule SupportDesk.RegressionAgent do
  @moduledoc false

  alias Jido.{Joi, Memory}
  use Jido.Agent, name: "regression_agent", plugins: [Jido.Memory.Plugin]

  memory do
    index(:guides, operations: [search: SupportDesk.SearchGuides])
    graph(:guide_links, operations: [search: SupportDesk.SearchGuideLinks])

    collection :procedures, max_entries: 3 do
      schema(Joi.object(%{release: Joi.string(), summary: Joi.string()}))
    end
  end

  routes do
    signal_source("/examples/memory/regression")

    route "examples.memory.regression.approved", as: :approve do
      action %{key: key, value: value}, schema: Joi.map(), context: context do
        {:ok, context.agent_state, [Memory.remember(:procedures, key, value)]}
      end
    end

    route "examples.memory.regression.ask", SupportDesk.RegressionFlow, as: :ask do
      state(:unchanged)
      reply("examples.memory.regression.answer", from: output(:trace))
    end
  end
end

alias SupportDesk.{ArcanaDatabase, Inference, RegressionAgent, RelayGuideGraph}

fixture = fn model, prompt, _options ->
  %{content: [%{text: text}]} = List.last(prompt.messages)

  result =
    if String.contains?(text, "[G-REPAIR]") && String.contains?(text, "[PROC-4]") do
      "Check the queue, then select Prime [G-REPAIR] [PROC-4]."
    else
      "No verified repair."
    end

  Inference.fixture_reply(model, prompt, result)
end

ArcanaDatabase.with_repo(
  fn opts ->
    :ok = RelayGuideGraph.seed!(opts)
    agent = RegressionAgent.instantiate!(id: "repair-evaluator")

    approval =
      RegressionAgent.approve_signal!(%{
        key: "PROC-4",
        value: %{release: "v1.0", summary: "Check the queue before applying the verified repair."}
      })

    {:ok, agent, [_]} = RegressionAgent.cmd(agent, approval)

    context = %{arcana: opts, inference: Inference.from_args!(System.argv(), fixture)}
    question = "What does S17 refund charge alert mean, and what is the repair?"
    settings = [off: {:off, 0}, hybrid: {:hybrid, 0}, graph_with_procedure: {:graph, 1}, regression: {:graph, 0}]

    results =
      for {label, {mode, depth}} <- settings, into: %{} do
        signal = RegressionAgent.ask_signal!(%{question: question, mode: mode, depth: depth})
        start = System.monotonic_time(:microsecond)
        {:ok, _, [%{signal: reply}]} = RegressionAgent.cmd(agent, signal, context: context)
        {label, Map.put(reply.data, :turn_latency_us, System.monotonic_time(:microsecond) - start)}
      end

    %{
      off: %{sent_ids: []},
      hybrid: %{sent_ids: ["G-SYMPTOM"]},
      graph_with_procedure: %{sent_ids: ["G-SYMPTOM", "G-REPAIR", "PROC-4"]},
      regression: %{sent_ids: ["G-SYMPTOM"]}
    } = results

    %{call: %{model: model, model_input: [instructions | _]}, retrieval: %{depth: 1} = before} =
      results.graph_with_procedure

    %{call: %{model: ^model, model_input: [^instructions | _]}, retrieval: %{depth: 0} = after_change} =
      results.regression

    missing = Enum.map(before.passages, & &1.id) -- Enum.map(after_change.passages, & &1.id)
    ["G-REPAIR"] = missing
    false = results.regression.metrics.task_success

    if model == "fixture:support-desk" do
      true = results.graph_with_procedure.metrics.task_success
    end

    IO.puts(
      Jason.encode!(
        %{first_divergence: %{step: "retrieve", changed_graph_depth: [1, 0], lost: missing}, cases: results},
        pretty: true
      )
    )
  end,
  graph: true
)
