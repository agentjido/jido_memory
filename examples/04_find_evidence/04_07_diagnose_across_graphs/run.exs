Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.ReadDiagnosticGraph do
  @moduledoc false

  alias Jido.Joi
  alias SupportDesk.GraphStore

  use Jido.Action,
    name: "read_diagnostic_graph",
    schema: Joi.object(%{graph: Joi.enum(["account", "product", "experience"]), subject: Joi.any()})

  @impl true
  def run(%{graph: graph, subject: subject}, %{store: store, access: access}) do
    if graph in access do
      iri = GraphStore.iri("graph/" <> graph)
      entries = GraphStore.facts(store, iri, subject)
      {:ok, %{entries: entries, trace: %{graph: to_string(iri), subject: to_string(subject), decision: :opened}}}
    else
      {:error, :graph_access_denied}
    end
  end
end

defmodule SupportDesk.DiagnoseGraphFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.{GraphStore, Inference}

  use Jido.Flow,
    name: "diagnose_across_graphs",
    schema: Joi.object(%{ticket: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "read_account", [ticket <- input(:ticket), context <- context()] do
      {%{entries: facts} = account, trace} = read(context, "account", GraphStore.iri("case/" <> ticket))
      [device] = values(facts, "device")
      {:ok, %{account: account, device: device, trace: trace}}
    end

    step "read_product", [account <- result("read_account"), context <- context()] do
      {%{entries: facts} = product, trace} = read(context, "product", account.device)
      [version] = values(facts, "version")
      [name] = values(facts, "name")
      [lookalike] = values(facts, "same_name_as")
      {%{entries: other}, _} = read(context, "product", lookalike)
      [^name] = values(other, "name")

      checked = %{
        name: name,
        selected: to_string(account.device),
        rejected: to_string(lookalike),
        version: version,
        reason: :matched_account_device_id
      }

      {:ok, %{product: product, version: version, tests: values(facts, "tested_in"), ambiguity: checked, trace: trace}}
    end

    step "check_experience", [product <- result("read_product"), context <- context(), access <- context(:access)] do
      case "experience" in access do
        true ->
          checked =
            Enum.map(product.tests, fn subject ->
              {%{entries: facts}, trace} = read(context, "experience", subject)
              [tested] = values(facts, "tested_version")

              if tested == product.version do
                [procedure] = values(facts, "procedure")
                Map.merge(trace, %{decision: :accepted, tested_version: tested, procedure: procedure})
              else
                Map.merge(trace, %{decision: :wrong_version, tested_version: tested})
              end
            end)

          {:ok, %{checks: checked}}

        false ->
          {:ok, %{checks: [%{graph: graph_id("experience"), decision: :denied, reads: 0}]}}
      end
    end

    step "answer", [
      account <- result("read_account"),
      product <- result("read_product"),
      checks <- result("check_experience", :checks),
      inference <- context(:inference)
    ] do
      result =
        case Enum.filter(checks, &(&1.decision == :accepted)) do
          [%{subject: subject, procedure: repair}] ->
            "[#{product.trace.subject}] #{product.ambiguity.name} #{product.version}. [#{subject}] #{repair}"

          [] ->
            "No approved repair for #{product.ambiguity.name} #{product.version}."
        end

      {model_text, call} =
        Inference.call!(inference, [
          Context.system("Copy the verified diagnosis line, including citations."),
          Context.user("Diagnosis:\n#{result}")
        ])

      {:ok,
       %{
         trace: %{
           hops: [account.trace, product.trace | checks],
           ambiguity: product.ambiguity,
           answer: result,
           model_text: model_text,
           call: call
         }
       }}
    end

    output(result("answer"))
  end

  defp read(context, graph, subject) do
    {:ok, %{entries: entries, trace: trace}} =
      Memory.access(context, :graph, :diagnostic, :facts, %{graph: graph, subject: subject})

    {%{entries: entries}, trace}
  end

  defp graph_id(name), do: to_string(GraphStore.iri("graph/" <> name))

  defp values(facts, name) do
    property = GraphStore.iri("property/" <> name)
    for {^property, object} <- facts, do: value(object)
  end

  defp value(%RDF.Literal{} = literal), do: RDF.Literal.value(literal)
  defp value(iri), do: iri
end

defmodule SupportDesk.GraphDiagnosisAgent do
  @moduledoc false
  use Jido.Agent, name: "graph_diagnosis_agent", plugins: [Jido.Memory.Plugin]

  memory do
    graph(:diagnostic, operations: [facts: SupportDesk.ReadDiagnosticGraph])
  end

  routes do
    signal_source("/examples/memory/diagnosis")

    route "examples.memory.diagnosis.ask", SupportDesk.DiagnoseGraphFlow, as: :ask do
      state(:unchanged)
      reply("examples.memory.diagnosis.answer", from: output(:trace))
    end
  end
end

alias SupportDesk.{GraphDiagnosisAgent, GraphStore, Inference}

fixture = fn model, prompt, _options ->
  %{content: [%{text: "Diagnosis:\n" <> result}]} = List.last(prompt.messages)
  Inference.fixture_reply(model, prompt, result)
end

database =
  Path.join(System.tmp_dir!(), "jido-memory-graph-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false))

{:ok, store} = TripleStore.open(database, schema: :quad)

try do
  put = fn graph, subject, facts ->
    triples = Enum.map(facts, fn {name, value} -> {GraphStore.iri("property/" <> name), value} end)
    :ok = GraphStore.put(store, GraphStore.iri("graph/" <> graph), GraphStore.iri(subject), triples)
  end

  device = GraphStore.iri("product/relay-s2")
  other = GraphStore.iri("product/relay-d1")
  tested = GraphStore.iri("test/relay-s2-prime")
  obsolete = GraphStore.iri("test/relay-v1-reset")
  procedure = "Select Prime from the Operations Relay menu."

  put.("account", "case/T-17", [{"device", device}])
  put.("product", "product/relay-d1", [{"name", "Relay"}, {"version", "v1"}])

  put.("product", "product/relay-s2", [
    {"name", "Relay"},
    {"version", "v2"},
    {"same_name_as", other},
    {"tested_in", obsolete},
    {"tested_in", tested}
  ])

  put.("experience", "test/relay-s2-prime", [{"tested_version", "v2"}, {"procedure", procedure}])
  put.("experience", "test/relay-v1-reset", [{"tested_version", "v1"}, {"procedure", "Use Factory Reset."}])

  agent = GraphDiagnosisAgent.instantiate!(id: "graph-support")
  signal = GraphDiagnosisAgent.ask_signal!(%{ticket: "T-17"})
  inference = Inference.from_args!(System.argv(), fixture)

  results =
    for {role, access} <- [full: ["experience"], limited: []], into: %{} do
      {:ok, _, [%{signal: reply}]} =
        GraphDiagnosisAgent.cmd(agent, signal,
          context: %{store: store, access: ["account", "product" | access], inference: inference}
        )

      {role, reply.data}
    end

  %{ambiguity: %{reason: :matched_account_device_id, version: "v2"}, hops: [_, _ | checked]} = results.full
  [:accepted, :wrong_version] = checked |> Enum.map(& &1.decision) |> Enum.sort()
  %{hops: [_, _, %{decision: :denied, reads: 0}]} = results.limited
  %{content: allowed} = List.last(results.full.call.model_input)
  %{content: denied} = List.last(results.limited.call.model_input)
  true = String.contains?(allowed, procedure)
  false = String.contains?(allowed, "Factory Reset")
  false = String.contains?(denied, [procedure, "Factory Reset"])

  IO.puts(Jason.encode!(results, pretty: true))
after
  TripleStore.close(store)
  File.rm_rf!(database)
end
