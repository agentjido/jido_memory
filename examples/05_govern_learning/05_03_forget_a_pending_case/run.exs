Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.ForgottenCasesMigration do
  use Ecto.Migration

  def up do
    create table(:example_forgotten_cases, primary_key: false) do
      add(:case_key, :text, primary_key: true)
      add(:request_id, :text, null: false)
    end
  end
end

defmodule SupportDesk.ForgetCaseStore do
  @moduledoc false

  import Ecto.Query
  alias Arcana.{Chunk, Collection, Document}
  alias Arcana.Graph.Entity

  def index(job, opts) do
    repo = Keyword.fetch!(opts, :repo)

    locked(repo, job.key, fn ->
      if forgotten?(repo, job.key) do
        {:ok, %{decision: :tombstoned, request_id: job.request_id}}
      else
        case Arcana.ingest(
               job.text,
               Keyword.merge(index_opts(opts), collection: job.key, source_id: "case", replace: true)
             ) do
          {:ok, doc} -> {:ok, %{decision: :indexed, request_id: job.request_id, document_id: doc.id}}
          {:error, reason} -> {:error, reason}
        end
      end
    end)
  end

  def forget(key, request_id, opts) do
    repo = Keyword.fetch!(opts, :repo)

    locked(repo, key, fn ->
      repo.insert_all("example_forgotten_cases", [%{case_key: key, request_id: request_id}],
        conflict_target: :case_key,
        on_conflict: :nothing
      )

      {:ok, docs} = Arcana.list_documents(Keyword.put(opts, :collection, key))

      case delete_docs(docs, index_opts(opts)) do
        :ok -> {:ok, %{decision: :forgotten, request_id: request_id, deleted: Enum.map(docs, & &1.id)}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def forgotten?(repo, key) do
    %{rows: [[present]]} =
      repo.query!("SELECT EXISTS (SELECT 1 FROM example_forgotten_cases WHERE case_key = $1)", [key])

    present
  end

  def counts(repo, key) do
    collection = from(c in Collection, where: c.name == ^key, select: c.id)
    documents = from(d in Document, where: d.collection_id in subquery(collection), select: d.id)

    %{
      documents: repo.aggregate(documents, :count),
      chunks: repo.aggregate(from(c in Chunk, where: c.document_id in subquery(documents)), :count),
      graph_entities: repo.aggregate(from(e in Entity, where: e.collection_id in subquery(collection)), :count)
    }
  end

  defp locked(repo, key, fun) do
    repo.transact(fn ->
      repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])
      fun.()
    end)
  end

  defp index_opts(opts) do
    Keyword.merge(opts,
      graph: true,
      entity_extractor: fn _text, _ -> {:ok, [%{name: "Case T-17", type: "case"}]} end,
      relationship_extractor: fn _, _, _ -> {:ok, []} end
    )
  end

  defp delete_docs(docs, opts) do
    Enum.reduce_while(docs, :ok, fn doc, :ok ->
      case Arcana.delete(doc.id, opts) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end

defmodule SupportDesk.DelayedIndexWorker do
  @moduledoc false
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts), do: {:ok, %{opts: opts, pending: nil}}

  @impl true
  def handle_call({:delay, job}, _from, state), do: {:reply, :queued, %{state | pending: job}}

  def handle_call(:release, _from, state) do
    {:reply, SupportDesk.ForgetCaseStore.index(state.pending, state.opts), %{state | pending: nil}}
  end
end

defmodule SupportDesk.ForgetIndexedCase do
  @moduledoc false
  alias Jido.Joi

  use Jido.Action, name: "forget_indexed_case", schema: Joi.object(%{key: Joi.string()})

  @impl true
  def run(%{key: key}, %{arcana: options, signal: signal}) do
    SupportDesk.ForgetCaseStore.forget(key, signal.id, options)
  end
end

defmodule SupportDesk.CaseTombstone do
  @moduledoc false
  alias Jido.Joi

  use Jido.Action, name: "read_case_tombstone", schema: Joi.object(%{key: Joi.string()})

  @impl true
  def run(%{key: key}, %{arcana: options}) do
    repo = Keyword.fetch!(options, :repo)
    {:ok, %{blocked: SupportDesk.ForgetCaseStore.forgotten?(repo, key)}}
  end
end

defmodule SupportDesk.ForgetCaseFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}

  use Jido.Flow,
    name: "forget_case",
    schema: Joi.object(%{key: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "delete", [key <- input(:key), context <- context()] do
      with {:ok, trace} <- Memory.access(context, :index, :cases, :delete, %{key: key}) do
        {:ok, %{trace: trace}, [Memory.forget(:summaries, key)]}
      end
    end

    output(result("delete"))
  end
end

defmodule SupportDesk.ForgottenCaseAgent do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.{CaseTombstone, ForgetIndexedCase, Inference}

  use Jido.Agent, name: "forgotten_case_agent", plugins: [Jido.Memory.Plugin]

  memory do
    index(:cases, operations: [delete: ForgetIndexedCase, tombstone: CaseTombstone])

    collection :summaries, max_entries: 4 do
      schema(Joi.object(%{key: Joi.string(), summary: Joi.string()}))
    end
  end

  routes do
    signal_source("/examples/memory/forget")

    route "examples.memory.forget.seed", as: :seed do
      action %{key: key, summary: summary},
        schema: Joi.object(%{key: Joi.string(), summary: Joi.string()}),
        context: context do
        {:ok, context.agent_state, [Memory.remember(:summaries, key, %{key: key, summary: summary})]}
      end
    end

    route "examples.memory.forget.delete", SupportDesk.ForgetCaseFlow, as: :delete do
      state(:unchanged)
      reply("examples.memory.forget.deleted", from: output(:trace))
    end

    route "examples.memory.forget.ask", as: :ask do
      action %{key: key},
        schema: Joi.object(%{key: Joi.string()}),
        output_schema: Joi.object(%{trace: Joi.map()}),
        context: context do
        question(key, context)
      end

      state(:unchanged)
      reply("examples.memory.forget.answer", from: output(:trace))
    end
  end

  defp question(key, %{inference: inference} = context) do
    {:ok, %{blocked: blocked}} = Memory.access(context, :index, :cases, :tombstone, %{key: key})
    {:ok, rows} = Memory.recall(context, :summaries, where: %{key: key})

    result =
      case {blocked, rows} do
        {false, [%{value: value}]} -> value.summary
        _ -> "No retained case evidence."
      end

    {reply, call} =
      Inference.call!(inference, [
        Context.system("Use only the case evidence line. Copy it exactly."),
        Context.user("Case evidence line:\n#{result}")
      ])

    {:ok,
     %{trace: %{access: if(blocked, do: :tombstoned, else: :allow), model_text: reply, call: call, answer: result}}}
  end
end

alias Jido.Memory

alias SupportDesk.{
  ArcanaDatabase,
  DelayedIndexWorker,
  ForgetCaseStore,
  ForgottenCaseAgent,
  ForgottenCasesMigration,
  Inference
}

fixture = fn model, prompt, _options ->
  %{content: [%{text: "Case evidence line:\n" <> result}]} = List.last(prompt.messages)
  Inference.fixture_reply(model, prompt, result)
end

ArcanaDatabase.with_repo(
  fn opts ->
    repo = Keyword.fetch!(opts, :repo)
    Ecto.Migrator.up(repo, 3, ForgottenCasesMigration, log: false)

    key = "forgotten-T-17-" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    summary = "Refund accepted under RESOLUTION-FORGET-17."
    job = %{key: key, text: summary, request_id: "close-T-17"}
    {:ok, %{decision: :indexed}} = ForgetCaseStore.index(job, opts)
    %{documents: 1, chunks: 1, graph_entities: 1} = before = ForgetCaseStore.counts(repo, key)

    agent = ForgottenCaseAgent.instantiate!(id: "privacy-support")
    {:ok, agent, [_]} = ForgottenCaseAgent.cmd(agent, ForgottenCaseAgent.seed_signal!(%{key: key, summary: summary}))
    {:ok, [_]} = Memory.recall(agent, :summaries)
    {:ok, worker} = DelayedIndexWorker.start_link(opts)
    :queued = GenServer.call(worker, {:delay, job})

    signal = ForgottenCaseAgent.delete_signal!(%{key: key})

    {:ok, agent, [%Jido.Memory.Directive.Forget{}, %{signal: deleted}]} =
      ForgottenCaseAgent.cmd(agent, signal, context: %{arcana: opts})

    {:ok, []} = Memory.recall(agent, :summaries)
    {:ok, %{decision: :tombstoned}} = late = GenServer.call(worker, :release)
    :ok = GenServer.stop(worker)
    {:ok, restarted} = DelayedIndexWorker.start_link(opts)
    :queued = GenServer.call(restarted, {:delay, job})
    {:ok, %{decision: :tombstoned}} = replay = GenServer.call(restarted, :release)
    :ok = GenServer.stop(restarted)

    %{documents: 0, chunks: 0, graph_entities: 0} = remaining = ForgetCaseStore.counts(repo, key)

    ask = ForgottenCaseAgent.ask_signal!(%{key: key})
    context = %{arcana: opts, inference: Inference.from_args!(System.argv(), fixture)}
    {:ok, _, [%{signal: answer}]} = ForgottenCaseAgent.cmd(agent, ask, context: context)
    %{access: :tombstoned, answer: "No retained case evidence."} = answer.data

    public_trace = %{
      before: before,
      deletion: deleted.data,
      late_write: elem(late, 1),
      after_worker_restart: elem(replay, 1),
      remaining: remaining,
      recall: answer.data
    }

    json = Jason.encode!(public_trace, pretty: true)
    false = String.contains?(json, summary)
    IO.puts(json)
  end,
  graph: true
)
