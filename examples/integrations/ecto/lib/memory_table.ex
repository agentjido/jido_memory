defmodule JidoMemory.Examples.Ecto.SQLiteRepo do
  use Ecto.Repo, otp_app: :jido_memory_ecto_examples, adapter: Ecto.Adapters.SQLite3
end

defmodule JidoMemory.Examples.Ecto.PostgresRepo do
  use Ecto.Repo, otp_app: :jido_memory_ecto_examples, adapter: Ecto.Adapters.Postgres
end

defmodule JidoMemory.Examples.Ecto.Tables do
  @moduledoc false
  use Ecto.Migration

  def up do
    Jido.Persistence.Ecto.Migration.up(version: 1)

    create table(:example_memory_resolutions, primary_key: false) do
      add(:agent_id, :string, primary_key: true)
      add(:ticket_key, :string, primary_key: true)
      add(:summary, :text, null: false)
      add(:source_signal_id, :string, null: false)
    end

    create table(:example_memory_receipts, primary_key: false) do
      add(:request_id, :string, primary_key: true)
      add(:digest, :binary, null: false)
    end
  end
end

defmodule JidoMemory.Examples.Ecto.MemoryTable do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  def store(repo, request) do
    receipt = %{request_id: request.request_id, digest: digest(request)}
    record = Map.take(request, [:agent_id, :ticket_key, :summary, :source_signal_id])

    repo.transact(fn ->
      case repo.insert_all("example_memory_receipts", [receipt], on_conflict: :nothing, conflict_target: [:request_id]) do
        {1, _} ->
          {1, _} =
            repo.insert_all("example_memory_resolutions", [record],
              on_conflict: {:replace, [:summary, :source_signal_id]},
              conflict_target: [:agent_id, :ticket_key]
            )

          {:ok, %{request_id: request.request_id, decision: :stored}}

        {0, _} ->
          existing =
            repo.one!(
              from(item in "example_memory_receipts",
                where: item.request_id == ^request.request_id,
                select: item.digest
              )
            )

          if existing == receipt.digest,
            do: {:ok, %{request_id: request.request_id, decision: :replayed}},
            else: {:error, :request_id_conflict}
      end
    end)
  end

  def get(repo, id, key) do
    repo.one(
      from(record in "example_memory_resolutions",
        where: record.agent_id == ^id and record.ticket_key == ^key,
        select: map(record, [:ticket_key, :summary, :source_signal_id])
      )
    )
  end

  def counts(repo) do
    %{
      records: repo.aggregate("example_memory_resolutions", :count),
      receipts: repo.aggregate("example_memory_receipts", :count)
    }
  end

  defp digest(request) do
    values = [request.agent_id, request.ticket_key, request.summary, request.source_signal_id]
    :crypto.hash(:sha256, Jason.encode!(values))
  end
end
