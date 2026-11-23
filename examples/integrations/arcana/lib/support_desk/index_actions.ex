defmodule SupportDesk.FetchDocument do
  @moduledoc false
  use Jido.Action, name: "fetch_document", schema: Jido.Joi.object(%{guide: Jido.Joi.map()})

  @impl true
  def run(%{guide: %{repo_path: repo, commit: commit, path: "guides/" <> _ = path} = guide}, _context) do
    git_path = Map.get(guide, :git_path, path)

    case System.cmd("git", ["-C", repo, "show", commit <> ":" <> git_path], stderr_to_stdout: true) do
      {text, 0} ->
        if String.valid?(text), do: {:ok, %{guide: guide, text: text}}, else: {:error, :invalid_guide_text}

      {_output, _code} ->
        {:error, :guide_not_found}
    end
  end
end

defmodule SupportDesk.IndexDocument do
  @moduledoc false
  alias Jido.Joi

  use Jido.Action,
    name: "index_document",
    schema: Joi.object(%{guide: Joi.map(), text: Joi.string()}),
    output_schema: Joi.object(%{job_id: Joi.string(), decision: Joi.atom()})

  @impl true
  def run(%{guide: guide, text: text}, %{arcana: opts}) do
    with {:ok, job} <- SupportDesk.GuideIndex.index(guide, text, opts) do
      {:ok, %{job_id: job.id, decision: Map.get(job, :decision, :attempted)}}
    end
  end
end

defmodule SupportDesk.IndexStatus do
  @moduledoc false
  use Jido.Action, name: "index_status", schema: Jido.Joi.object(%{job_id: Jido.Joi.string()})

  @impl true
  def run(%{job_id: id}, %{arcana: opts}) do
    {:ok, %{job: SupportDesk.GuideIndex.status(Keyword.fetch!(opts, :repo), id)}}
  end
end

defmodule SupportDesk.SearchGuides do
  @moduledoc false
  alias Jido.Joi

  use Jido.Action,
    name: "search_guides",
    schema:
      Joi.object(%{
        package: Joi.string(),
        version: Joi.string(),
        question: Joi.string(),
        path: Joi.string() |> Joi.default(""),
        mode: Joi.enum([:keyword, :vector, :hybrid]) |> Joi.optional(),
        limit: Joi.integer(gte: 1) |> Joi.optional(),
        threshold: Joi.number() |> Joi.optional(),
        vector_weight: Joi.number() |> Joi.optional(),
        keyword_weight: Joi.number() |> Joi.optional()
      })

  @impl true
  def run(%{package: package, version: version, question: question} = params, %{arcana: opts}) do
    opts =
      case Map.get(params, :path, "") do
        "" -> opts
        path -> Keyword.put(opts, :source_id, path)
      end

    search = Map.take(params, [:mode, :limit, :threshold, :vector_weight, :keyword_weight])
    SupportDesk.GuideIndex.search(package, version, question, Keyword.merge(opts, Map.to_list(search)))
  end
end

defmodule SupportDesk.SearchGuideLinks do
  @moduledoc false
  alias Jido.Joi
  alias SupportDesk.{GuideIndex, RelayGuideGraph}

  use Jido.Action,
    name: "search_guide_links",
    schema:
      Joi.object(%{
        package: Joi.string(),
        version: Joi.string(),
        question: Joi.string(),
        depth: Joi.integer(gte: 0)
      })

  @impl true
  def run(%{package: package, version: version, question: question, depth: depth}, %{arcana: opts}) do
    options =
      opts
      |> Keyword.merge(mode: :hybrid, limit: 2, threshold: 0.5)
      |> RelayGuideGraph.options()
      |> Keyword.put(:graph_depth, depth)

    GuideIndex.search(package, version, question, options)
  end
end

defmodule SupportDesk.ListGuideDocuments do
  @moduledoc false
  alias Jido.Joi
  alias SupportDesk.GuideIndex

  use Jido.Action,
    name: "list_guide_documents",
    schema: Joi.object(%{package: Joi.string(), version: Joi.string()})

  @impl true
  def run(%{package: package, version: version}, %{arcana: opts}) do
    with {:ok, documents} <-
           Arcana.list_documents(
             Keyword.merge(opts, collection: GuideIndex.collection(package, version), status: :completed)
           ) do
      {:ok, %{documents: documents}}
    end
  end
end

defmodule SupportDesk.IndexGuideFlow do
  @moduledoc false
  alias Jido.Joi
  alias SupportDesk.{FetchDocument, IndexDocument, IndexStatus}

  use Jido.Flow,
    name: "index_a_guide",
    schema: Joi.object(%{guide: Joi.map()}),
    output_schema: Joi.object(%{indexed: Joi.map()})

  flow do
    step("fetch",
      action: FetchDocument,
      params: %{guide: input(:guide)}
    )

    step("index", action: IndexDocument, params: result("fetch"))

    step("status", action: IndexStatus, params: %{job_id: result("index", :job_id)})

    step "report", [index <- result("index"), status <- result("status")] do
      {:ok, %{indexed: %{job: status.job, decision: index.decision}}}
    end

    output(result("report"))
  end
end

defmodule SupportDesk.ReindexCollection do
  @moduledoc false
  alias Jido.Joi
  alias SupportDesk.IndexGuideFlow

  use Jido.Action,
    name: "reindex_collection",
    schema: Joi.object(%{guides: Joi.list(Joi.map()), limit: Joi.integer(gte: 1)}),
    output_schema: Joi.object(%{report: Joi.map()})

  @impl true
  def run(%{guides: guides, limit: limit}, context) do
    {scheduled, deferred} = Enum.split(guides, limit)

    jobs =
      Enum.map(scheduled, fn guide ->
        case Jido.Exec.run(IndexGuideFlow, %{guide: guide}, context) do
          {:ok, %{indexed: indexed}} -> indexed
          {:error, reason} -> %{path: guide.path, decision: :repair_required, reason: Exception.message(reason)}
        end
      end)

    {:ok, %{report: %{jobs: jobs, scheduled: length(scheduled), deferred: length(deferred)}}}
  end
end
