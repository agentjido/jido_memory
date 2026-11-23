defmodule SupportDesk.GuideIndex.Job do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "example_index_jobs" do
    field(:collection, :string)
    field(:guide_path, :string)
    field(:revision, :string)
    field(:checksum, :string)
    field(:status, :string)
    field(:attempts, :integer)
    field(:document_id, Ecto.UUID)
    field(:error, :string)
  end
end

defmodule SupportDesk.GuideIndex do
  @moduledoc false

  alias SupportDesk.GuideIndex.Job

  def collection(package, version), do: package <> "@" <> version

  def checksum(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower)

  def job_id(collection, path), do: checksum(collection <> "\n" <> path)

  def status(repo, id) do
    case repo.get(Job, id) do
      nil -> %{id: id, status: "pending"}
      job -> job |> Map.from_struct() |> Map.delete(:__meta__)
    end
  end

  def index(guide, text, opts) do
    %{package: package, version: version, path: path, commit: revision} = guide
    repo = Keyword.fetch!(opts, :repo)
    collection = collection(package, version)
    id = job_id(collection, path)
    checksum = checksum(text)

    repo.transact(fn ->
      repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [id])
      previous = status(repo, id)

      if match?(%{status: "indexed", checksum: ^checksum, revision: ^revision}, previous) &&
           Arcana.count_documents(repo: repo, collection: collection, source_id: path, status: :completed) == {:ok, 1} do
        {:ok, Map.put(previous, :decision, :already_indexed)}
      else
        job =
          ingest(guide, text, collection, opts)
          |> Map.merge(%{
            id: id,
            attempts: Map.get(previous, :attempts, 0) + 1,
            checksum: checksum,
            revision: revision,
            collection: collection,
            guide_path: path
          })

        {1, _} =
          repo.insert_all(Job, [job],
            conflict_target: :id,
            on_conflict: {:replace_all_except, [:id]}
          )

        {:ok, job}
      end
    end)
  end

  defp ingest(guide, text, collection, opts) do
    metadata = guide |> Map.drop([:repo_path]) |> Map.put(:checksum, checksum(text))

    case Arcana.ingest(
           text,
           Keyword.merge(opts,
             collection: collection,
             metadata: metadata,
             source_id: guide.path,
             replace: true
           )
         ) do
      {:ok, document} ->
        %{status: "indexed", document_id: document.id, error: nil}

      {:error, reason} ->
        %{status: "failed", document_id: nil, error: inspect(reason)}
    end
  end

  def search(package, version, question, opts) do
    collection = collection(package, version)
    opts = Keyword.put(opts, :collection, collection)
    opts = Keyword.put_new(opts, :mode, :hybrid)
    opts = Keyword.put_new(opts, :limit, 4)

    with {:ok, hits} <- Arcana.search(question, opts),
         {:ok, documents} <- Arcana.get_document_metadata(Enum.map(hits, & &1.document_id), opts) do
      evidence =
        for hit <- hits,
            %{metadata: %{"package" => ^package, "version" => ^version} = citation} <- [documents[hit.document_id]] do
          %{chunk_id: hit.id, document_id: hit.document_id, score: hit.score, citation: citation, text: hit.text}
        end

      {:ok, %{collection: collection, evidence: evidence, candidate_count: length(hits)}}
    end
  end
end
