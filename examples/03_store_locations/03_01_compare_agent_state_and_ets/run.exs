Code.require_file("../../support/inference.exs", __DIR__)
Code.require_file("../../00_start_here/00_02_answer_from_memory/agent.exs", __DIR__)

defmodule SupportDesk.SharedMemoryAgent do
  @moduledoc false

  use Jido.AI.Agent, name: "shared_memory_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.Joi
  alias Jido.Memory.Store.ETS
  alias SupportDesk.AnswerFlow

  ai do
    reasoning AnswerFlow do
      instructions("""
      If there is no message labeled Memory evidence, reply exactly: I don't have a prior resolution in memory.
      Otherwise, answer in one short sentence using that evidence and cite the ticket key.
      """)
    end
  end

  memory AnswerFlow do
    external_collection :resolutions, store: {ETS, %{name: SupportDesk.SharedResolutions, scope: "support"}} do
      schema(Joi.object(%{issue: Joi.string(), summary: Joi.string(), internal_note: Joi.string()}))
    end

    read(:prior_resolutions, collection: :resolutions, filters: [:issue], expose: [:summary], limit: 1)
  end
end

defmodule SupportDesk.CompareStores do
  @moduledoc false

  alias Jido.{AgentServer, Memory, Persistence, Session, Signal}
  alias Jido.Memory.Store.ETS
  alias SupportDesk.{Inference, MemoryAgent, MemoryFixture, SharedMemoryAgent, SharedResolutions}

  @instance SupportDesk.SharedRecallInstance
  @question "What did we do the last time a customer was charged twice?"
  @no_evidence "I don't have a prior resolution in memory."

  def run(argv) do
    {params, context} = Inference.agent_config!(argv, MemoryFixture)
    params = Map.put(params, :input, @question)
    value = %{issue: "duplicate_charge", summary: "Refunded the second charge", internal_note: "Internal ledger note"}

    state_traces = compare_checkpoints(params, context, value)
    shared_traces = compare_shared_store(params, context, value)

    traces = %{agent_state: state_traces, ets: shared_traces}
    json = Jason.encode!(traces, pretty: true)
    IO.puts(json)
    false = String.contains?(json, ["Internal ledger note", "Unrelated scope note", "Private adapter metadata"])
  end

  defp compare_checkpoints(params, context, value) do
    original = MemoryAgent.instantiate!(id: "private-original")
    other = MemoryAgent.instantiate!(id: "private-other")
    write = MemoryAgent.resolve_signal!(%{key: "T-17", value: value})

    {:ok, committed, [_directive]} = MemoryAgent.cmd(original, write)
    {:ok, snapshot} = Persistence.snapshot(committed)
    {:ok, restored} = Persistence.restore(snapshot)

    question = MemoryAgent.request_signal!(params)
    {:ok, _, [%{signal: reply}]} = MemoryAgent.cmd(restored, question, context: context)
    {:ok, _, [%{signal: other_reply}]} = MemoryAgent.cmd(other, question, context: context)

    %{restored: with_evidence!(reply.data, write.id), another_agent: without_evidence!(other_reply.data, :allowed)}
  end

  defp compare_shared_store(params, context, value) do
    {:ok, owner} = ETS.start_link(name: SharedResolutions)
    {:ok, instance} = Jido.start_link(name: @instance)

    try do
      write = Signal.new!("examples.memory.shared.seeded", %{key: "T-17"}, source: "/examples/memory/shared-store")
      record = %{key: "T-17", value: value, source_signal_id: write.id, metadata: "Private adapter metadata"}
      :ok = ETS.put(SharedResolutions, "support", :resolutions, record)
      :ok = ETS.put(SharedResolutions, "finance", :resolutions, put_in(record.value.summary, "Unrelated scope note"))

      definition = SharedMemoryAgent.instantiate!(id: "shared-primary")
      {:error, :live_memory_required} = Memory.recall(definition, :resolutions)
      {:ok, primary} = Jido.start_agent(@instance, definition)
      {:ok, secondary} = Jido.start_agent(@instance, SharedMemoryAgent, id: "shared-secondary")
      :ok = AgentServer.await_ready(primary)
      :ok = AgentServer.await_ready(secondary)

      first = ask_live!(primary, params, context) |> with_evidence!(write.id)
      second = ask_live!(secondary, params, context) |> with_evidence!(write.id)
      :ok = :sys.suspend(owner)

      after_timeout =
        try do
          ask_live!(primary, params, context) |> without_evidence!(:store_timeout)
        after
          :ok = :sys.resume(owner)
        end

      :ok = GenServer.stop(owner)
      after_stop = ask_live!(primary, params, context) |> without_evidence!(:store_unavailable)

      %{first_agent: first, second_agent: second, after_timeout: after_timeout, after_owner_stop: after_stop}
    after
      Supervisor.stop(instance)
      if Process.alive?(owner), do: GenServer.stop(owner)
    end
  end

  defp ask_live!(server, params, context) do
    session = Session.new(id: "comparison-#{Jido.Id.uuid7()}")
    context = Map.put(context, :jido_ai_session, session)
    question = SharedMemoryAgent.request_signal!(params)
    {:ok, %{status: :committed, reply: reply}} = AgentServer.call(server, question, context: context, timeout: 120_000)
    reply.data
  end

  defp with_evidence!(%{status: :completed, output: answer, memory_trace: trace}, source) do
    %{decision: :allowed, records: [%{key: "T-17", source_signal_id: ^source}]} = trace.recall
    true = String.contains?(answer, "T-17")
    true = answer |> String.downcase() |> String.contains?("refund")
    Map.put(trace, :answer, answer)
  end

  defp without_evidence!(%{status: :completed, output: answer, memory_trace: trace}, decision) do
    %{decision: ^decision, records: []} = trace.recall
    [%{role: :system}, %{role: :user, content: @question}] = trace.model_input
    @no_evidence = String.trim(answer)
    Map.put(trace, :answer, answer)
  end
end

SupportDesk.CompareStores.run(System.argv())
