Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.AnswerGuideFlow do
  @moduledoc false

  alias Jido.Joi
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "answer_for_an_exact_release",
    schema: Joi.object(%{package: Joi.string(), version: Joi.string(), question: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step("search",
      action: SupportDesk.SearchGuides,
      params: %{package: input(:package), version: input(:version), question: input(:question)}
    )

    step "answer", [search <- result("search"), question <- input(:question), inference <- context(:inference)] do
      result = cite(search.evidence, search.collection)

      {reply, call} =
        Inference.call!(inference, [
          Context.system("Copy the result, including the release citation."),
          Context.user("Question: #{question}\nResult:\n#{result}")
        ])

      output = if String.trim(reply || "") == result, do: :used_model_answer, else: :used_verified_guide
      {:ok, %{trace: %{search: search, call: call, model_text: reply, output: output, answer: result}}}
    end

    output(result("answer"))
  end

  defp cite([], collection), do: "No indexed guide for #{collection}."

  defp cite([hit | _], collection), do: "[#{collection}/#{hit.citation["path"]}] " <> String.trim(hit.text)
end

defmodule SupportDesk.ExactGuideAgent do
  @moduledoc false
  use Jido.Agent, name: "exact_guide_agent"

  routes do
    signal_source("/examples/memory/guide")

    route "examples.memory.guide.index", SupportDesk.IndexGuideFlow, as: :index do
      state(:unchanged)
      reply("examples.memory.guide.indexed", from: output(:indexed))
    end

    route "examples.memory.guide.ask", SupportDesk.AnswerGuideFlow, as: :ask do
      state(:unchanged)
      reply("examples.memory.guide.answer", from: output(:trace))
    end
  end
end

alias SupportDesk.{ArcanaDatabase, ExactGuideAgent, Inference, LocalGuideRepo}

fixture = fn model, prompt, _options ->
  %{content: [%{text: input}]} = List.last(prompt.messages)
  [_, result] = String.split(input, "\nResult:\n")
  Inference.fixture_reply(model, prompt, result)
end

package = "support_kit"
path = "guides/refunds.md"

releases = [
  {"v1.0.0", %{path => "The standard refund window is 30 days."}},
  {"v2.0.0", %{path => "The standard refund window is 14 days."}}
]

ArcanaDatabase.with_repo(fn opts ->
  LocalGuideRepo.with_releases(releases, fn root, refs ->
    loader = ExactGuideAgent.instantiate!(id: "guide-loader")

    run = fn agent, signal, context ->
      {:ok, _, [%{signal: reply}]} = ExactGuideAgent.cmd(agent, signal, context: context)
      reply.data
    end

    jobs =
      for {version, _} <- releases do
        commit = Map.fetch!(refs, version)

        guide = %{
          repo_path: root,
          package: package,
          version: version,
          commit: commit,
          path: path,
          source_url: "https://example.test/#{package}/blob/#{commit}/#{path}"
        }

        %{job: %{status: "indexed"}} =
          indexed = run.(loader, ExactGuideAgent.index_signal!(%{guide: guide}), %{arcana: opts})

        indexed
      end

    reader = ExactGuideAgent.instantiate!(id: "guide-reader")
    context = %{arcana: opts, inference: Inference.from_args!(System.argv(), fixture)}

    answers =
      for {version, expected, excluded} <- [
            {"v1.0.0", "30 days", "14 days"},
            {"v2.0.0", "14 days", "30 days"},
            {"v3.0.0", "No indexed guide", "30 days"}
          ] do
        signal =
          ExactGuideAgent.ask_signal!(%{package: package, version: version, question: "What is the refund window?"})

        answer = run.(reader, signal, context)

        %{content: input} = List.last(answer.call.model_input)
        true = String.contains?(input, expected)
        false = String.contains?(input, excluded)
        true = String.contains?(answer.answer, version)

        case Map.fetch(refs, version) do
          {:ok, commit} ->
            [%{citation: %{"commit" => ^commit, "path" => ^path, "version" => ^version}}] = answer.search.evidence

          :error ->
            [] = answer.search.evidence
            false = String.contains?(input, "14 days")
        end

        answer
      end

    IO.puts(Jason.encode!(%{indexed_by: loader.id, answered_by: reader.id, jobs: jobs, answers: answers}, pretty: true))
  end)
end)
