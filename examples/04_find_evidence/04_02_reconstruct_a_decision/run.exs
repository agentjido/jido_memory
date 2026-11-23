Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.DatedFactsFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "reconstruct_a_refund_decision",
    schema: Joi.object(%{effective_on: Joi.string(), known_on: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "read_facts",
         [effective <- input(:effective_on), known <- input(:known_on), context <- context()] do
      {:ok,
       %{
         facts: %{
           account: resolve(context, "account:T-17", effective, known),
           policy: resolve(context, "refund-policy", effective, known)
         }
       }}
    end

    step "answer",
         [
           facts <- result("read_facts", :facts),
           effective <- input(:effective_on),
           known <- input(:known_on),
           inference <- context(:inference)
         ] do
      account = facts.account.selected
      policy = facts.policy.selected
      evidence = "[#{account.id}] Account tier: #{account.value}. [#{policy.id}] Refund window: #{policy.value}."

      {answer, call} =
        Inference.call!(inference, [
          Context.system("Copy only the evidence line, including both citations."),
          Context.user("Effective on #{effective}. Known on #{known}.\nEvidence line:\n#{evidence}")
        ])

      output = if String.trim(answer || "") == evidence, do: :used_model_answer, else: :used_verified_facts

      {:ok,
       %{
         trace: %{
           effective_on: effective,
           known_on: known,
           facts: facts,
           call: call,
           model_text: answer,
           answer: evidence,
           output: output
         }
       }}
    end

    output(result("answer"))
  end

  defp resolve(context, subject, effective, known) do
    {:ok, %{facts: facts}} =
      Memory.access(context, :graph, :dated_facts, :query, %{subject: subject, effective_on: effective})

    candidates =
      facts
      |> Enum.map(fn fact ->
        %{
          id: fact.id,
          value: fact.object,
          recorded_on: Map.fetch!(fact.metadata, "recorded_on"),
          valid_from: fact.valid_from,
          valid_to: fact.valid_to
        }
      end)
      |> Enum.sort_by(& &1.recorded_on, :desc)

    selected = Enum.find(candidates, &(&1.recorded_on <= known))
    %{selected: selected, candidates: Enum.map(candidates, &Map.drop(&1, [:value]))}
  end
end

defmodule SupportDesk.DatedFactsAgent do
  @moduledoc false
  use Jido.Agent, name: "dated_facts_agent", plugins: [Jido.Memory.Plugin]

  memory do
    graph(:dated_facts, operations: [query: SupportDesk.PalaceFacts])
  end

  routes do
    signal_source("/examples/memory/dated-facts")

    route "examples.memory.dates.ask", SupportDesk.DatedFactsFlow, as: :ask do
      state(:unchanged)
      reply("examples.memory.dates.answer", from: output(:trace))
    end
  end
end

alias Jido.Memory.MemPalace
alias SupportDesk.{DatedFactsAgent, Inference}

fixture = fn model, prompt, _options ->
  %{content: [%{text: text}]} = List.last(prompt.messages)
  [_, evidence] = String.split(text, "\nEvidence line:\n")
  Inference.fixture_reply(model, prompt, evidence)
end

database =
  Path.join(System.tmp_dir!(), "jido-memory-dates-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false))

File.mkdir!(database)
palace = [namespace: "refunds", backend: :local, backend_opts: [database: Path.join(database, "palace.sqlite3")]]

try do
  add = fn id, subject, predicate, value, valid_from, recorded_on, valid_to ->
    {:ok, fact} =
      MemPalace.graph_add(
        %{},
        %{
          id: id,
          subject: subject,
          predicate: predicate,
          object: value,
          valid_from: valid_from,
          valid_to: valid_to,
          metadata: %{recorded_on: recorded_on}
        },
        palace
      )

    fact
  end

  add.("account-v1", "account:T-17", "tier", "Silver", "2026-11-01", "2026-11-01", nil)

  {:ok, 1} =
    MemPalace.graph_invalidate(%{}, %{subject: "account:T-17", predicate: "tier", valid_to: "2026-11-10"}, palace)

  add.("account-v2", "account:T-17", "tier", "Gold", "2026-11-11", "2026-11-12", nil)
  add.("account-v3", "account:T-17", "tier", "Standard", "2026-11-11", "2026-11-21", nil)
  add.("policy-v1", "refund-policy", "window", "30 days", "2026-11-01", "2026-11-01", "2026-11-19")
  add.("policy-v2", "refund-policy", "window", "14 days", "2026-11-20", "2026-11-20", nil)

  {:ok, [expired]} = MemPalace.graph_query(%{}, [subject: "account:T-17", as_of: "2026-11-10"] ++ palace)
  %{id: "account-v1", valid_to: "2026-11-10"} = expired

  agent = DatedFactsAgent.instantiate!(id: "refund-audit")
  context = %{palace: palace, inference: Inference.from_args!(System.argv(), fixture)}

  paths = [
    {"2026-11-19", "2026-11-19", "account-v2", "policy-v1"},
    {"2026-11-19", "2026-11-22", "account-v3", "policy-v1"},
    {"2026-11-22", "2026-11-22", "account-v3", "policy-v2"}
  ]

  traces =
    Enum.map(paths, fn {effective, known, account, policy} ->
      signal = DatedFactsAgent.ask_signal!(%{effective_on: effective, known_on: known})
      {:ok, _, [%{signal: reply}]} = DatedFactsAgent.cmd(agent, signal, context: context)
      %{facts: %{account: %{selected: %{id: ^account}}, policy: %{selected: %{id: ^policy}}}, call: call} = reply.data
      %{content: input} = List.last(call.model_input)
      true = String.contains?(input, "[#{account}]")
      true = String.contains?(input, "[#{policy}]")
      2 = length(Regex.scan(~r/\[(account|policy)-v\d\]/, input))
      reply.data
    end)

  IO.puts(Jason.encode!(%{ended_fact: %{id: expired.id, valid_to: expired.valid_to}, queries: traces}, pretty: true))
after
  File.rm_rf!(database)
end
