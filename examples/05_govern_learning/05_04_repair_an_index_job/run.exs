Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.RepairIndexFlow do
  @moduledoc false
  alias Jido.Joi

  use Jido.Flow,
    name: "resume_release_import",
    schema: Joi.object(%{guides: Joi.list(Joi.map()), limit: Joi.integer(gte: 1), failed_job: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step("previous",
      action: SupportDesk.IndexStatus,
      params: %{job_id: input(:failed_job)}
    )

    step("resume",
      action: SupportDesk.ReindexCollection,
      needs: ["previous"],
      params: %{guides: input(:guides), limit: input(:limit)}
    )

    step "report", [previous <- result("previous"), resumed <- result("resume")] do
      {:ok, %{trace: %{previous: previous.job, import: resumed.report}}}
    end

    output(result("report"))
  end
end

defmodule SupportDesk.IndexRepairAgent do
  @moduledoc false
  use Jido.Agent, name: "repair_index_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}
  alias SupportDesk.SearchGuides

  memory do
    index(:guides, operations: [search: SearchGuides])
  end

  routes do
    signal_source("/examples/memory/index-repair")

    route "examples.memory.index-repair.resume", SupportDesk.RepairIndexFlow, as: :resume do
      state(:unchanged)
      reply("examples.memory.index-repair.completed", from: output(:trace))
    end

    route "examples.memory.index-repair.search", as: :search do
      action input,
        schema: Joi.object(%{package: Joi.string(), version: Joi.string(), question: Joi.string()}),
        output_schema: Joi.object(%{trace: Joi.map()}),
        context: context do
        with {:ok, search} <- Memory.access(context, :index, :guides, :search, input) do
          {:ok, %{trace: search}}
        end
      end

      state(:unchanged)
      reply("examples.memory.index-repair.results", from: output(:trace))
    end
  end
end

alias ReqLLM.Context
alias SupportDesk.{ArcanaDatabase, GuideEmbedder, GuideIndex, IndexRepairAgent, Inference, LocalGuideRepo}

fixture = fn model, prompt, _options ->
  %{content: [%{text: "Verified guide:\n" <> evidence}]} = List.last(prompt.messages)
  Inference.fixture_reply(model, prompt, evidence)
end

recovery = "guides/restore.md"
verify = "guides/verify.md"
check = "guides/check.md"

releases = [
  {"v1.0",
   %{
     recovery => "Restore the release by selecting Resume on the stalled worker. REPAIR_FIXTURE.",
     verify => "Verify that the resumed worker reports Ready.",
     check => "Confirm the alert count is zero before closing the ticket."
   }}
]

ArcanaDatabase.with_repo(fn opts ->
  LocalGuideRepo.with_releases(releases, fn root, %{"v1.0" => commit} ->
    package = "repair_kit_" <> String.slice(commit, 0, 12)
    collection = GuideIndex.collection(package, "v1.0")
    repair_id = GuideIndex.job_id(collection, recovery)

    guides =
      for path <- [recovery, verify, check],
          do: %{
            repo_path: root,
            package: package,
            version: "v1.0",
            commit: commit,
            path: path,
            source_url: "https://example.test/repair-kit/blob/#{commit}/#{path}"
          }

    run = fn id, limit ->
      agent = IndexRepairAgent.instantiate!(id: id)
      signal = IndexRepairAgent.resume_signal!(%{guides: guides, limit: limit, failed_job: repair_id})
      {:ok, _, [%{signal: reply}]} = IndexRepairAgent.cmd(agent, signal, context: %{arcana: opts})
      reply.data
    end

    old_embedder = Application.fetch_env!(:arcana, :embedder)

    interrupted =
      try do
        Application.put_env(:arcana, :embedder, {GuideEmbedder, fail_on: "REPAIR_FIXTURE"})
        run.("first-index-worker", 2)
      after
        Application.put_env(:arcana, :embedder, old_embedder)
      end

    %{
      previous: %{id: ^repair_id, status: "pending"},
      import: %{
        deferred: 1,
        jobs: [
          %{job: %{id: ^repair_id, status: "failed", attempts: 1}},
          %{job: %{status: "indexed", document_id: verified_id}}
        ]
      }
    } = interrupted

    resumed = run.("new-index-worker", 3)

    %{
      previous: %{id: ^repair_id, status: "failed"},
      import: %{
        deferred: 0,
        jobs: [
          %{job: %{id: ^repair_id, status: "indexed", attempts: 2}},
          %{decision: :already_indexed, job: %{document_id: ^verified_id}},
          %{job: %{status: "indexed", attempts: 1}}
        ]
      }
    } = resumed

    repeat = run.("repeat-index-worker", 3)
    true = Enum.all?(repeat.import.jobs, &(&1.decision == :already_indexed))

    for %{path: path} <- guides do
      {:ok, 1} =
        Arcana.count_documents(Keyword.merge(opts, collection: collection, source_id: path, status: :completed))
    end

    reader = IndexRepairAgent.instantiate!(id: "guide-reader")

    question =
      IndexRepairAgent.search_signal!(%{
        package: package,
        version: "v1.0",
        question: "How do I restore the stalled worker?"
      })

    {:ok, _, [%{signal: results}]} = IndexRepairAgent.cmd(reader, question, context: %{arcana: opts})

    %{citation: %{"path" => ^recovery}, text: text} =
      Enum.find(results.data.evidence, &(&1.citation["path"] == recovery))

    evidence = "[#{collection}/#{recovery}] #{text}"
    inference = Inference.from_args!(System.argv(), fixture)

    {reply, call} =
      Inference.call!(inference, [
        Context.system("Copy the verified guide with its release citation."),
        Context.user("Verified guide:\n#{evidence}")
      ])

    IO.puts(
      Jason.encode!(
        %{interrupted: interrupted, resumed: resumed, repeat: repeat, answer: evidence, model_text: reply, call: call},
        pretty: true
      )
    )
  end)
end)
