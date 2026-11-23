Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.RankEvidenceFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  @package "ranked_refunds"
  @version "v1"

  use Jido.Flow,
    name: "compare_search_paths",
    schema: Joi.object(%{question: Joi.string(), effective_on: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "rank",
         [question <- input(:question), context <- context(), effective <- input(:effective_on)] do
      rankings =
        for mode <- [:keyword, :vector, :hybrid], into: %{} do
          search = %{
            package: @package,
            version: @version,
            question: question,
            mode: mode,
            vector_weight: 0.85,
            keyword_weight: 0.15
          }

          {:ok, %{evidence: hits}} = Memory.access(context, :index, :guides, :search, search)
          {mode, hits}
        end

      {:ok, %{rankings: Map.put(rankings, :time, by_date(context, effective))}}
    end

    step "check_sources",
         [rankings <- result("rank", :rankings), approved <- context(:approved), effective <- input(:effective_on)] do
      checks =
        rankings
        |> Map.values()
        |> List.flatten()
        |> Enum.uniq_by(& &1.document_id)
        |> Enum.map(&check(&1, approved, effective))

      ranked =
        Map.new(rankings, fn {mode, hits} ->
          {mode,
           Enum.map(hits, fn hit -> %{path: hit.citation["path"], document_id: hit.document_id, score: hit.score} end)}
        end)

      {:ok, %{ranking: ranked, checks: checks}}
    end

    step "answer", [review <- result("check_sources"), question <- input(:question), inference <- context(:inference)] do
      [%{path: path, text: text}] = Enum.filter(review.checks, &(&1.decision == :accepted))
      evidence = "[#{path}] #{text}"

      {reply, call} =
        Inference.call!(inference, [
          Context.system("Copy the verified evidence line with its citation."),
          Context.user("Question: #{question}\nVerified evidence:\n#{evidence}")
        ])

      output = if String.trim(reply || "") == evidence, do: :used_model_answer, else: :used_verified_evidence
      {:ok, %{trace: Map.merge(review, %{call: call, answer: evidence, model_text: reply, output: output})}}
    end

    output(result("answer"))
  end

  defp by_date(context, effective) do
    {:ok, %{documents: docs}} =
      Memory.access(context, :index, :guides, :list, %{package: @package, version: @version})

    docs
    |> Enum.filter(&(&1.metadata["effective_from"] <= effective))
    |> Enum.sort_by(& &1.metadata["effective_from"], :desc)
    |> Enum.map(&%{document_id: &1.id, citation: &1.metadata, score: nil, text: &1.content})
  end

  defp check(hit, approved, effective) do
    path = hit.citation["path"]
    reference = %{path: path, document_id: hit.document_id, effective_from: hit.citation["effective_from"]}

    case approved[path] do
      %{checksum: checksum, from: starts, until: ends} when starts <= effective and effective <= ends ->
        if hit.citation["checksum"] == checksum do
          Map.merge(reference, %{decision: :accepted, text: String.trim(hit.text)})
        else
          Map.put(reference, :decision, :rejected_revision)
        end

      nil ->
        Map.put(reference, :decision, :unapproved_source)

      _ ->
        Map.put(reference, :decision, :outside_effective_dates)
    end
  end
end

defmodule SupportDesk.RankingAgent do
  @moduledoc false
  use Jido.Agent, name: "evidence_ranking_agent", plugins: [Jido.Memory.Plugin]

  alias SupportDesk.{ListGuideDocuments, SearchGuides}

  memory do
    index(:guides, operations: [search: SearchGuides, list: ListGuideDocuments])
  end

  routes do
    signal_source("/examples/memory/rank")

    route "examples.memory.rank.ask", SupportDesk.RankEvidenceFlow, as: :ask do
      state(:unchanged)
      reply("examples.memory.rank.answer", from: output(:trace))
    end
  end
end

alias SupportDesk.{ArcanaDatabase, GuideIndex, Inference, RankingAgent}

fixture = fn model, prompt, _options ->
  %{content: [%{text: input}]} = List.last(prompt.messages)
  [_, line] = String.split(input, "\nVerified evidence:\n")
  Inference.fixture_reply(model, prompt, line)
end

policy = "guides/supported-policy.md"
retired = "guides/retired-policy.md"
dashboard = "guides/dashboard.md"
draft = "guides/pending-change.md"

documents = [
  {policy, "Reimburse a double card payment within 30 days.", "2026-11-05"},
  {retired, "Reimburse a double card payment within 60 days.", "2026-10-01"},
  {dashboard, "Refund duplicate charge deadline is a dashboard index. Restart the release service to reconnect.",
   "2026-11-17"},
  {draft, "Reimburse a double card payment within 5 days.", "2026-11-25"}
]

checksums = Map.new(documents, fn {path, text, _from} -> {path, GuideIndex.checksum(text)} end)

approved = %{
  policy => %{checksum: checksums[policy], from: "2026-11-05", until: "2026-11-30"},
  retired => %{checksum: checksums[retired], from: "2026-10-01", until: "2026-11-04"},
  draft => %{checksum: checksums[draft], from: "2026-11-25", until: "2026-12-31"}
}

ArcanaDatabase.with_repo(fn opts ->
  for {path, text, effective_from} <- documents do
    guide = %{
      package: "ranked_refunds",
      version: "v1",
      path: path,
      commit: "fixture-v1",
      effective_from: effective_from
    }

    {:ok, %{status: "indexed"}} = GuideIndex.index(guide, text, opts)
  end

  agent = RankingAgent.instantiate!(id: "rank-searches")

  signal =
    RankingAgent.ask_signal!(%{question: "What is the refund duplicate charge deadline?", effective_on: "2026-11-19"})

  context = %{arcana: opts, approved: approved, inference: Inference.from_args!(System.argv(), fixture)}
  {:ok, _, [%{signal: reply}]} = RankingAgent.cmd(agent, signal, context: context)
  %{ranking: rankings, checks: checks, call: call} = reply.data

  [%{path: ^dashboard} | _] = rankings.keyword
  [%{path: ^dashboard}, %{path: ^policy}, %{path: ^retired}] = rankings.time
  true = Enum.any?(rankings.vector, &(&1.path == policy))
  true = Enum.any?(rankings.hybrid, &(&1.path == policy))
  [%{path: ^policy}] = Enum.filter(checks, &(&1.decision == :accepted))

  %{content: input} = List.last(call.model_input)
  true = String.contains?(input, "[#{policy}] Reimburse a double card payment within 30 days.")
  false = String.contains?(input, ["60 days", "5 days", "dashboard index"])

  IO.puts(Jason.encode!(reply.data, pretty: true))
end)
