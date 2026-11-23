Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.ReadGraphNote do
  @moduledoc false

  alias Jido.Joi
  alias SupportDesk.GraphStore

  use Jido.Action, name: "read_graph_note", schema: Joi.object(%{key: Joi.string(), scope: Joi.string()})

  @impl true
  def run(%{scope: scope, key: key}, %{graph_access: access, graph_store: store}) do
    {:ok, %{read: read(store, access, scope, key)}}
  end

  defp read(store, access, scope, key) do
    case Map.fetch(access, scope) do
      {:ok, graph} ->
        predicate = GraphStore.iri("content")

        hit =
          case GraphStore.facts(store, graph, GraphStore.iri("record/" <> key)) do
            [{^predicate, literal}] -> %{key: key, content: RDF.Literal.value(literal)}
            [] -> nil
          end

        %{scope: scope, decision: :allow, graph: to_string(graph), hit: hit}

      :error ->
        %{scope: scope, decision: :deny, graph: nil, hit: nil}
    end
  end
end

defmodule SupportDesk.GraphRecallFlow do
  @moduledoc false

  alias Jido.Joi
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "recall_from_a_named_graph",
    schema: Joi.object(%{key: Joi.string(), scope: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step("authorize_and_read",
      action: SupportDesk.ReadGraphNote,
      params: %{key: input(:key), scope: input(:scope)}
    )

    step "answer", [lookup <- result("authorize_and_read"), inference <- context(:inference)] do
      read = lookup.read
      result = if read.hit, do: "[#{read.hit.key}] #{read.hit.content}", else: "No approved evidence."

      {answer, call} =
        Inference.call!(inference, [
          Context.system(
            "Repeat the approved evidence line exactly. With no approved evidence, say No approved evidence."
          ),
          Context.user("Approved evidence line:\n#{result}")
        ])

      {:ok, %{trace: %{read: read, model: call, model_text: answer}}}
    end

    output(result("answer"))
  end
end

defmodule SupportDesk.GraphRecallAgent do
  @moduledoc false
  use Jido.Agent, name: "graph_recall_agent"

  routes do
    signal_source("/examples/memory/graph")

    route "examples.memory.graph.ask", SupportDesk.GraphRecallFlow, as: :ask do
      state(:unchanged)
      reply("examples.memory.graph.answer", from: output(:trace))
    end
  end
end

alias SupportDesk.{GraphRecallAgent, GraphStore, Inference}

fixture = fn model, prompt, _options ->
  %{content: [%{text: "Approved evidence line:\n" <> result}]} = List.last(prompt.messages)
  Inference.fixture_reply(model, prompt, result)
end

inference = Inference.from_args!(System.argv(), fixture)

path =
  Path.join(System.tmp_dir!(), "jido-memory-kg-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false))

private_graph = GraphStore.iri("graph/agent/alice")
shared_graph = GraphStore.iri("graph/project/refunds")
private_id = to_string(private_graph)
shared_id = to_string(shared_graph)
key = "refund-guide"
subject = GraphStore.iri("record/" <> key)
predicate = GraphStore.iri("content")
preference = "Alice prefers a callback before any refund."
note = "The project uses the standard refund form."

try do
  {:ok, store} = TripleStore.open(path, schema: :quad)

  try do
    :ok = GraphStore.put(store, private_graph, subject, [{predicate, preference}])
    :ok = GraphStore.put(store, shared_graph, subject, [{predicate, note}])
  after
    :ok = TripleStore.close(store)
  end

  {:ok, reopened} = TripleStore.open(path, schema: :quad)

  try do
    alice = GraphRecallAgent.instantiate!(id: "alice")
    bob = GraphRecallAgent.instantiate!(id: "bob")

    ask = fn agent, scope, access ->
      question = GraphRecallAgent.ask_signal!(%{key: key, scope: scope})
      context = %{graph_store: reopened, graph_access: access, inference: inference}
      {:ok, _, [%{signal: reply}]} = GraphRecallAgent.cmd(agent, question, context: context)
      Map.put(reply.data, :agent, agent.id)
    end

    alice_private = ask.(alice, "private", %{"private" => private_graph})
    bob_shared = ask.(bob, "project", %{"project" => shared_graph})
    bob_denied = ask.(bob, "private", %{"project" => shared_graph})

    %{read: %{decision: :allow, graph: ^private_id, hit: %{key: ^key, content: ^preference}}} = alice_private
    %{read: %{decision: :allow, graph: ^shared_id, hit: %{key: ^key, content: ^note}}} = bob_shared
    %{read: %{decision: :deny, graph: nil, hit: nil}} = bob_denied

    for {answer, line} <- [
          {alice_private, "[#{key}] #{preference}"},
          {bob_shared, "[#{key}] #{note}"},
          {bob_denied, "No approved evidence."}
        ] do
      input = "Approved evidence line:\n" <> line
      %{content: ^input} = List.last(answer.model.model_input)
    end

    IO.puts(
      Jason.encode!(%{reopened: true, alice_private: alice_private, bob_shared: bob_shared, bob_denied: bob_denied},
        pretty: true
      )
    )
  after
    :ok = TripleStore.close(reopened)
  end
after
  File.rm_rf!(path)
end
