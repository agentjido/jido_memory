Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.CompareReleasesFlow do
  @moduledoc false

  alias Jido.Joi
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "compare_guide_releases",
    schema:
      Joi.object(%{
        package: Joi.string(),
        old: Joi.string(),
        new: Joi.string(),
        question: Joi.string(),
        query: Joi.string(),
        old_path: Joi.string(),
        new_path: Joi.string(),
        anchor: Joi.string()
      }),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step("older",
      action: SupportDesk.SearchGuides,
      params: %{package: input(:package), version: input(:old), question: input(:query), path: input(:old_path)}
    )

    step("newer",
      action: SupportDesk.SearchGuides,
      params: %{package: input(:package), version: input(:new), question: input(:query), path: input(:new_path)}
    )

    step "compare",
         [
           older <- result("older"),
           newer <- result("newer"),
           question <- input(:question),
           anchor <- input(:anchor),
           inference <- context(:inference)
         ] do
      evidence = [select(older, "A", anchor), select(newer, "B", anchor)]
      excerpts = Enum.map_join(evidence, "\n\n", &"[#{&1.reference}] #{&1.label}\n#{&1.text}")

      {reply, call} =
        Inference.call!(inference, [
          Context.system("Compare the two releases using the excerpts. Answer in two short lines. Cite [A] and [B]."),
          Context.user("Question: #{question}\nVersioned evidence:\n#{excerpts}")
        ])

      {output, answer} = cited_answer(reply, evidence)

      {:ok,
       %{
         trace: %{
           sources: evidence,
           call: call,
           model_text: reply,
           output: output,
           answer: answer
         }
       }}
    end

    output(result("compare"))
  end

  defp select(%{collection: release, evidence: [first | _] = passages}, reference, anchor) do
    passage = Enum.find(passages, first, &String.contains?(&1.text, anchor))

    %{
      reference: reference,
      label: release <> "/" <> passage.citation["path"],
      citation: passage.citation,
      text: excerpt(passage.text, anchor),
      chunk_id: passage.chunk_id
    }
  end

  defp select(%{collection: release, evidence: []}, _reference, _anchor) do
    raise "No indexed evidence for #{release}"
  end

  defp excerpt(text, ""), do: String.slice(text, 0, 790)

  defp excerpt(text, anchor) do
    case String.split(text, anchor, parts: 2) do
      [prefix, suffix] ->
        String.trim(
          String.slice(prefix, -min(80, String.length(prefix)), 80) <>
            anchor <>
            String.slice(suffix, 0, 690)
        )

      [text] ->
        excerpt(text, "")
    end
  end

  defp cited_answer(reply, evidence) do
    if is_binary(reply) && Enum.all?(evidence, &Regex.match?(reference_pattern(&1), reply)) do
      answer = Enum.reduce(evidence, reply, &Regex.replace(reference_pattern(&1), &2, "[#{&1.label}]"))
      {:used_model_comparison, answer}
    else
      {:used_cited_excerpts, Enum.map_join(evidence, "\n\n", &"[#{&1.label}] #{&1.text}")}
    end
  end

  defp reference_pattern(%{reference: reference}), do: ~r/[\[【]\s*#{reference}\s*[\]】]/
end

defmodule SupportDesk.GuideLibraryAgent do
  @moduledoc false
  use Jido.Agent, name: "versioned_guide_library_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}
  alias SupportDesk.ReindexCollection

  memory do
    index(:guides, operations: [reindex: ReindexCollection])
  end

  routes do
    signal_source("/examples/memory/guide-library")

    route "examples.memory.guide-library.index", as: :index do
      action input,
        schema: Joi.object(%{guides: Joi.list(Joi.map()), limit: Joi.integer(gte: 1)}),
        output_schema: Joi.object(%{report: Joi.map()}),
        context: context do
        Memory.access(context, :index, :guides, :reindex, input)
      end

      state(:unchanged)
      reply("examples.memory.guide-library.indexed", from: output(:report))
    end

    route "examples.memory.guide-library.compare", SupportDesk.CompareReleasesFlow, as: :compare do
      state(:unchanged)
      reply("examples.memory.guide-library.comparison", from: output(:trace))
    end
  end
end

defmodule SupportDesk.GuideLibrary do
  @moduledoc false

  import Ecto.Query
  alias SupportDesk.{ArcanaDatabase, GuideCatalog, GuideLibraryAgent}

  def run(manifest, comparison, inference) do
    guides = for %{guides: found} <- manifest, guide <- found, do: guide
    [first | remaining] = guides
    ready = Enum.filter(manifest, &(&1.status == :ready))
    unresolved = Enum.filter(manifest, &(&1.status in [:repair_required, :no_guides, :no_releases]))
    IO.puts(:stderr, "Guide library: #{length(ready)} releases with #{length(guides)} guide paths.")

    ArcanaDatabase.with_repo(fn opts ->
      [%{job: %{id: interrupted_id, status: "indexed"}}] =
        import_batches([first], opts, "first-import")

      completed = import_batches(guides, opts, "resumed-import")
      [%{job: %{id: ^interrupted_id}, decision: :already_indexed} | _] = completed
      true = length(remaining) + 1 == length(completed)
      repeat = import_batches(guides, opts, "repeat-import")
      true = length(repeat) == length(guides)

      indexed = for %{job: %{status: "indexed"} = job} <- completed, do: job
      repairs = Enum.reject(completed, &match?(%{job: %{status: "indexed"}}, &1))
      rechecked = Enum.count(repeat, &(&1.decision == :already_indexed))
      true = length(indexed) == rechecked
      unique_indexed!(opts, indexed)

      IO.puts(
        Jason.encode!(
          %{
            packages: manifest |> Enum.map(& &1.package) |> Enum.uniq() |> length(),
            release_counts: Enum.frequencies_by(manifest, & &1.status),
            release_discovery: discovery_counts(manifest),
            unresolved: unresolved,
            indexed_guides: length(indexed),
            duplicates: 0,
            failed_jobs: repairs,
            interrupted_after: 1,
            resumed_job_id: interrupted_id,
            repeat_skipped: rechecked,
            comparison: compare(comparison, inference, opts)
          },
          pretty: true
        )
      )
    end)
  end

  def compare(%{old: old, new: new} = comparison, inference, opts) do
    verifier = GuideLibraryAgent.instantiate!(id: "guide-reader")
    signal = GuideLibraryAgent.compare_signal!(comparison)
    %{sources: [older, newer]} = answer = deliver(verifier, signal, %{arcana: opts, inference: inference})
    %{"version" => ^old} = older.citation
    %{"version" => ^new} = newer.citation
    %{content: prompt} = List.last(answer.call.model_input)
    true = older.citation["commit"] != newer.citation["commit"]

    for {source, expected_path} <- [{older, comparison.old_path}, {newer, comparison.new_path}] do
      true = String.contains?(prompt, source.label)
      true = String.contains?(answer.answer, source.label)
      true = expected_path == "" || source.citation["path"] == expected_path
      true = comparison.anchor == "" || String.contains?(source.text, comparison.anchor)
    end

    answer
  end

  def public_manifest(catalog, cache) do
    entries = GuideCatalog.entries(catalog)
    manifest = GuideCatalog.discover_public(entries, cache)
    true = MapSet.new(Enum.map(entries, & &1.package)) == MapSet.new(Enum.map(manifest, & &1.package))
    manifest
  end

  defp import_batches(guides, opts, label) do
    agent = GuideLibraryAgent.instantiate!(id: label)

    guides
    |> Enum.chunk_every(32)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {batch, index} ->
      signal = GuideLibraryAgent.index_signal!(%{guides: batch, limit: length(batch)})
      %{jobs: jobs, deferred: 0} = deliver(agent, signal, %{arcana: opts})
      if rem(index, 25) == 0, do: IO.puts(:stderr, "Guide library: #{label} processed #{index * 32} jobs.")
      jobs
    end)
  end

  defp deliver(agent, signal, context) do
    {:ok, _, [%{signal: reply}]} = GuideLibraryAgent.cmd(agent, signal, context: context)
    reply.data
  end

  defp unique_indexed!(opts, indexed) do
    repo = Keyword.fetch!(opts, :repo)
    expected = MapSet.new(indexed, &{&1.collection, &1.guide_path})
    collections = indexed |> Enum.map(& &1.collection) |> Enum.uniq()

    counts =
      from(d in Arcana.Document,
        join: c in assoc(d, :collection),
        where: c.name in ^collections,
        group_by: [c.name, d.source_id],
        select: {{c.name, d.source_id}, count(d.id)}
      )
      |> repo.all()
      |> Map.new()

    true = Enum.all?(expected, &(counts[&1] == 1))
  end

  defp discovery_counts(manifest) do
    manifest
    |> Enum.flat_map(&Map.get(&1, :discovery, []))
    |> Enum.frequencies()
  end
end

alias SupportDesk.{ArcanaDatabase, GuideCatalog, GuideLibrary, Inference, LocalGuideRepo}

fixture = fn model, prompt, _options ->
  %{content: [%{text: text}]} = List.last(prompt.messages)
  [_, passages] = String.split(text, "\nVersioned evidence:\n", parts: 2)
  [older, newer] = String.split(passages, ~r/^\[[AB]\] /m, trim: true)

  reply =
    Enum.map_join([{"A", older}, {"B", newer}], "\n", fn {reference, passage} ->
      [_, text] = String.split(passage, "\n", parts: 2)
      "[#{reference}] #{String.trim(text)}"
    end)

  Inference.fixture_reply(model, prompt, reply)
end

inference = Inference.from_args!(System.argv(), fixture)

if System.get_env("MEMORY_GUIDE_CATALOG") == "1" do
  [package, old, new] = System.get_env("MEMORY_GUIDE_COMPARE", "jido,2.3.3,3.0.0-beta.3") |> String.split(",")
  default_question = "How does each release define Agent state?"
  question = System.get_env("MEMORY_GUIDE_QUESTION", default_question)

  {paths, anchor} =
    if {package, old, new, question} == {"jido", "2.3.3", "3.0.0-beta.3", default_question} do
      {"guides/agents.md,guides/agents/define-and-instantiate-an-agent.livemd", "use Jido.Agent"}
    else
      {",", ""}
    end

  [old_path, new_path] = System.get_env("MEMORY_GUIDE_PATHS", paths) |> String.split(",", parts: 2)

  comparison = %{
    package: package,
    old: old,
    new: new,
    question: question,
    query: if(anchor == "", do: question, else: anchor),
    old_path: old_path,
    new_path: new_path,
    anchor: anchor
  }

  if System.get_env("MEMORY_GUIDE_COMPARE_ONLY") == "1" do
    ArcanaDatabase.with_repo(fn opts ->
      IO.puts(Jason.encode!(GuideLibrary.compare(comparison, inference, opts), pretty: true))
    end)
  else
    cache = System.fetch_env!("MEMORY_GUIDE_CACHE")
    manifest = GuideLibrary.public_manifest(Path.join(__DIR__, "catalog.tsv"), cache)
    GuideLibrary.run(manifest, comparison, inference)
  end
else
  path = "guides/refunds.md"

  releases = [
    {"v1.0.0", %{path => "Refund within 30 days."}},
    {"v2.0.0", %{path => "Refund within 14 days."}},
    {"v3.0.0", %{"README.md" => "This release has no guide."}}
  ]

  LocalGuideRepo.with_releases(releases, fn root, refs ->
    entry = %{package: "library_fixture", repository: "example/support", prefix: "."}
    manifest = GuideCatalog.discover(entry, {:ok, root}, {:ok, ["1.0.0", "4.0.0"]})
    old = Map.fetch!(refs, "v1.0.0")
    new = Map.fetch!(refs, "v2.0.0")

    [
      %{version: "1.0.0", status: :ready, commit: ^old, discovery: [:hex, :git]},
      %{version: "2.0.0", status: :ready, commit: ^new, discovery: [:git]},
      %{version: "3.0.0", status: :no_guides},
      %{version: "4.0.0", status: :repair_required, reason: :hex_release_has_no_matching_git_tag}
    ] = manifest

    question = "What is the refund window?"

    comparison = %{
      package: "library_fixture",
      old: "1.0.0",
      new: "2.0.0",
      question: question,
      query: question,
      old_path: path,
      new_path: path,
      anchor: ""
    }

    GuideLibrary.run(manifest, comparison, inference)
  end)
end
