defmodule SupportDesk.ArcanaRepo do
  use Ecto.Repo, otp_app: :jido_memory_arcana_examples, adapter: Ecto.Adapters.Postgres
end

defmodule SupportDesk.GuideIndexMigration do
  use Ecto.Migration

  def up do
    Arcana.Migration.up(dimensions: SupportDesk.GuideEmbedder.dimensions([]))

    create table(:example_index_jobs, primary_key: false) do
      add(:id, :text, primary_key: true)
      add(:collection, :text, null: false)
      add(:guide_path, :text, null: false)
      add(:revision, :text, null: false)
      add(:checksum, :text, null: false)
      add(:status, :text, null: false)
      add(:attempts, :integer, null: false)
      add(:document_id, :binary_id)
      add(:error, :text)
    end
  end
end

defmodule SupportDesk.GuideGraphMigration do
  use Ecto.Migration

  def up, do: Arcana.Graph.Migration.up(dimensions: SupportDesk.GuideEmbedder.dimensions([]))
end

defmodule SupportDesk.ArcanaDatabase do
  @moduledoc false

  alias SupportDesk.{ArcanaRepo, GuideGraphMigration, GuideIndexMigration}

  def with_repo(fun, options \\ []) do
    {:ok, repo} = ArcanaRepo.start_link(connection_options() ++ [types: Arcana.PostgrexTypes])

    try do
      Ecto.Migrator.up(ArcanaRepo, 1, GuideIndexMigration, log: false, log_migrations_sql: false)

      if Keyword.get(options, :graph, false) do
        Ecto.Migrator.up(ArcanaRepo, 2, GuideGraphMigration, log: false, log_migrations_sql: false)
      end

      fun.(repo: ArcanaRepo)
    after
      Supervisor.stop(repo)
    end
  end

  defp connection_options do
    case System.get_env("MEMORY_POSTGRES_URL") do
      nil ->
        [
          socket_dir: System.fetch_env!("MEMORY_POSTGRES_SOCKET"),
          port: String.to_integer(System.get_env("MEMORY_POSTGRES_PORT", "5432")),
          username: System.fetch_env!("MEMORY_POSTGRES_USER"),
          database: System.fetch_env!("MEMORY_POSTGRES_DATABASE")
        ]

      url ->
        [url: url]
    end
  end
end

defmodule SupportDesk.GuideEmbedder do
  @moduledoc false
  @behaviour Arcana.Embedder

  @concepts [
    ~r/refund|reimburse|money back/i,
    ~r/charge|payment|card/i,
    ~r/release|version|install/i,
    ~r/restart|reboot|resume/i,
    ~r/connect|network|wifi/i,
    ~r/verify|confirm|check/i,
    ~r/window|days|deadline/i
  ]

  @impl true
  def dimensions(_opts), do: 8

  @impl true
  def embed(text, opts) do
    case Keyword.get(opts, :fail_on) do
      marker when is_binary(marker) ->
        if String.contains?(text, marker), do: {:error, :fixture_failure}, else: vector(text)

      nil ->
        vector(text)
    end
  end

  defp vector(text) do
    {:ok, [0.1 | Enum.map(@concepts, fn pattern -> if Regex.match?(pattern, text), do: 1.0, else: 0.0 end)]}
  end
end
