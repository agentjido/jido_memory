Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.GraphGuideFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  @package "relay_kit"
  @version "v1.0"

  use Jido.Flow,
    name: "follow_a_guide_link",
    schema: Joi.object(%{question: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "compare_searches", [question <- input(:question), context <- context()] do
      query = %{package: @package, version: @version, question: question}
      hybrid_query = Map.merge(query, %{mode: :hybrid, limit: 2, threshold: 0.5})

      with {:ok, hybrid} <- Memory.access(context, :index, :guides, :search, hybrid_query),
           {:ok, graph} <- Memory.access(context, :graph, :guide_links, :search, Map.put(query, :depth, 1)),
           {:ok, direct} <- Memory.access(context, :graph, :guide_links, :search, Map.put(query, :depth, 0)) do
        {:ok, %{search: %{hybrid: hybrid, graph: graph, direct_mentions: direct}}}
      end
    end

    step "answer", [
      search <- result("compare_searches", :search),
      question <- input(:question),
      inference <- context(:inference)
    ] do
      approved =
        Enum.filter(search.graph.evidence, &(&1.citation["path"] in ["guides/symptoms.md", "guides/repair.md"]))

      evidence = Enum.map_join(approved, "\n", &"[#{@version}/#{&1.citation["path"]}] #{&1.text}")

      {reply, call} =
        Inference.call!(inference, [
          Context.system("Explain the fault and give the repair. Use both passages and include both citations."),
          Context.user("Question: #{question}\nApproved evidence:\n#{evidence}")
        ])

      citations = Enum.map(approved, &"#{@version}/#{&1.citation["path"]}")
      valid = is_binary(reply) && String.contains?(reply, "Prime") && Enum.all?(citations, &String.contains?(reply, &1))

      {:ok,
       %{
         trace: %{
           search: search,
           required_citations: citations,
           call: call,
           model_text: reply,
           answer: if(valid, do: reply, else: evidence)
         }
       }}
    end

    output(result("answer"))
  end
end

defmodule SupportDesk.GraphGuideAgent do
  @moduledoc false
  use Jido.Agent, name: "graph_guide_agent", plugins: [Jido.Memory.Plugin]

  memory do
    index(:guides, operations: [search: SupportDesk.SearchGuides])
    graph(:guide_links, operations: [search: SupportDesk.SearchGuideLinks])
  end

  routes do
    signal_source("/examples/memory/graph-guide")

    route "examples.memory.graph-guide.ask", SupportDesk.GraphGuideFlow, as: :ask do
      state(:unchanged)
      reply("examples.memory.graph-guide.answer", from: output(:trace))
    end
  end
end

alias SupportDesk.{ArcanaDatabase, GraphGuideAgent, Inference, RelayGuideGraph}

fixture = fn model, prompt, _options ->
  %{content: [%{text: text}]} = List.last(prompt.messages)
  [_, evidence] = String.split(text, "\nApproved evidence:\n")
  Inference.fixture_reply(model, prompt, evidence)
end

symptom = "guides/symptoms.md"
repair = "guides/repair.md"

ArcanaDatabase.with_repo(
  fn opts ->
    :ok = RelayGuideGraph.seed!(opts)

    agent = GraphGuideAgent.instantiate!(id: "relay-support")
    signal = GraphGuideAgent.ask_signal!(%{question: "What does S17 refund charge alert mean, and what is the repair?"})
    context = %{arcana: opts, inference: Inference.from_args!(System.argv(), fixture)}
    {:ok, _, [%{signal: reply}]} = GraphGuideAgent.cmd(agent, signal, context: context)
    %{search: search, call: call} = reply.data

    [^symptom] = Enum.map(search.hybrid.evidence, & &1.citation["path"])
    [^symptom] = Enum.map(search.direct_mentions.evidence, & &1.citation["path"])
    [^repair, ^symptom] = Enum.sort(Enum.map(search.graph.evidence, & &1.citation["path"]))
    true = Enum.all?(search.graph.evidence, &(&1.citation["version"] == "v1.0"))

    %{content: input} = List.last(call.model_input)
    true = String.contains?(input, "[v1.0/#{symptom}]")
    true = String.contains?(input, "[v1.0/#{repair}]")
    false = String.contains?(input, ["Replace Node", "v2.0"])

    IO.puts(Jason.encode!(reply.data, pretty: true))
  end,
  graph: true
)
