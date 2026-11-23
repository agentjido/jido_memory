Code.require_file("../../support/inference.exs", __DIR__)
Code.require_file("agent.exs", __DIR__)

defmodule SupportDesk.LostAcknowledgementExample do
  @moduledoc false

  alias Jido.AgentServer
  alias JidoMemory.Examples.Ecto.{MemoryTable, PostgresRepo, SQLiteRepo, Tables}
  alias ReqLLM.Context
  alias SupportDesk.Inference
  alias SupportDesk.PendingMemoryAgent, as: Agent

  @instance SupportDesk.MemoryExampleInstance

  def run(argv) do
    inference = Inference.from_args!(argv, &fixture/3)
    driver = System.get_env("MEMORY_ECTO_DRIVER", "sqlite")
    {repo, options, scratch} = database!(driver)

    {:ok, repository} = repo.start_link(options)

    try do
      :ok = Ecto.Migrator.up(repo, 1, Tables, log: false)

      {:ok, instance} =
        Jido.start_link(
          name: @instance,
          namespace: "examples/lost-acknowledgement",
          persistence: {Jido.Persistence.Ecto, repo: repo}
        )

      try do
        trace = exercise(repo, inference)
        IO.puts(Jason.encode!(Map.put(trace, :driver, driver), pretty: true))
      after
        Supervisor.stop(instance)
      end
    after
      Supervisor.stop(repository)
      if scratch, do: File.rm_rf!(scratch)
    end
  end

  defp exercise(repo, inference) do
    id = "support-desk"
    key = "T-17"
    summary = "Refunded the second charge."
    server = start_agent!(id)
    queue = Agent.queue_signal!(%{ticket_key: key, summary: summary})
    %{reply: %{data: %{decision: :queued, request: request}}, agent_address: address} = dispatch!(server, queue)
    nil = MemoryTable.get(repo, id, key)
    {:ok, %{decision: :stored} = receipt} = MemoryTable.store(repo, request)
    %{pending: ^request, acknowledged: nil} = pending!(server)
    counts = %{records: 1, receipts: 1}
    ^counts = MemoryTable.counts(repo)

    :ok = Jido.stop_agent(@instance, id)
    {:ok, restarted} = Jido.activate_agent(@instance, address)
    :ok = AgentServer.await_ready(restarted)
    %{pending: ^request, acknowledged: nil} = pending!(restarted)
    {:ok, %{decision: :replayed} = replay} = MemoryTable.store(repo, request)
    {:error, :request_id_conflict} = MemoryTable.store(repo, %{request | summary: "Conflicting payload."})
    ^counts = MemoryTable.counts(repo)

    operation_id = request.request_id
    ack = Agent.acknowledge_signal!(%{request_id: replay.request_id})

    %{reply: %{data: %{decision: :acknowledged, request_id: ^operation_id} = acknowledged}} =
      dispatch!(restarted, ack, memory_writer: true)

    %{pending: nil, acknowledged: ^operation_id} = pending!(restarted)
    lookup = Agent.read_signal!(%{ticket_key: key})
    %{reply: %{data: %{record: record}}} = dispatch!(restarted, lookup, memory_repo: repo)
    source = queue.id
    %{ticket_key: ^key, summary: ^summary, source_signal_id: ^source} = record
    line = "[#{record.ticket_key}] #{record.summary}"

    {answer, call} =
      Inference.call!(inference, [
        Context.system("Copy the stored resolution exactly. Output only that line."),
        Context.user("Stored resolution:\n#{line}")
      ])

    ^line = String.trim(answer)

    %{
      committed_request: request,
      first_write: receipt,
      fault: :acknowledgement_lost,
      restored_request: request,
      retried_write: replay,
      confirmed: acknowledged,
      database: counts,
      later_turn: %{record: record, model: call, answer: answer}
    }
  end

  defp start_agent!(id) do
    {:ok, server} = Jido.start_agent(@instance, Agent, id: id)
    :ok = AgentServer.await_ready(server)
    server
  end

  defp pending!(server) do
    %{reply: %{data: pending}} = dispatch!(server, Agent.pending_signal!(%{}))
    pending
  end

  defp dispatch!(server, signal, context \\ []) do
    {:ok, %{status: :committed, durability: :durable} = turn} =
      AgentServer.call(server, signal, context: Map.new(context))

    turn
  end

  defp database!("sqlite") do
    scratch = Path.join(System.tmp_dir!(), "jido-memory-sqlite-#{Jido.Id.uuid7()}")
    File.mkdir!(scratch)
    {SQLiteRepo, [database: Path.join(scratch, "memory.db"), pool_size: 1], scratch}
  end

  defp database!("postgres") do
    options =
      if socket = System.get_env("MEMORY_POSTGRES_SOCKET") do
        [
          socket_dir: socket,
          port: String.to_integer(System.get_env("MEMORY_POSTGRES_PORT", "5432")),
          username: System.fetch_env!("MEMORY_POSTGRES_USER"),
          database: System.fetch_env!("MEMORY_POSTGRES_DATABASE")
        ]
      else
        [url: System.fetch_env!("MEMORY_POSTGRES_URL")]
      end

    {PostgresRepo, options, nil}
  end

  defp fixture(model, prompt, _options) do
    %{content: [%{text: "Stored resolution:\n" <> line}]} = List.last(prompt.messages)
    Inference.fixture_reply(model, prompt, line)
  end
end

SupportDesk.LostAcknowledgementExample.run(System.argv())
