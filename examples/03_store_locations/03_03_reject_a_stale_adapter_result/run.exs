Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.StaleAdapter do
  @moduledoc false
  @behaviour Jido.Memory.Store

  alias Jido.Memory.Store.ETS

  @impl true
  defdelegate validate_config(config), to: ETS

  @impl true
  defdelegate recall(config, collection, filters, limit, context), to: ETS
end

defmodule SupportDesk.VerifySourceFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "verify_source_before_inference",
    schema: Joi.object(%{key: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  @missing "I don't have a verified resolution."

  flow do
    step "retrieve", key <- input(:key), inline: [context: context] do
      with {:ok, records} <- Memory.recall(context, :resolutions, where: %{ticket_key: key}, limit: 1) do
        {:ok, %{candidate: List.first(records)}}
      end
    end

    step "check_revision",
         [hit <- result("retrieve", :candidate), key <- input(:key), source <- context(:source_index)] do
      {:ok, check_revision(hit, Map.fetch!(source, key))}
    end

    step "answer", [check <- result("check_revision"), inference <- context(:inference)] do
      line = if check.projected, do: "[#{check.projected.key}] #{check.projected.summary}", else: @missing

      {model_text, call} =
        Inference.call!(inference, [
          Context.system("""
          Output only one line. If there is no verified resolution, say exactly: I don't have a verified resolution.
          Otherwise, copy the verified ticket line exactly.
          """),
          Context.user("Verified resolution result:\n#{line}")
        ])

      decision = if String.trim(model_text || "") == line, do: :model_copied, else: :used_verified_result

      {:ok,
       %{trace: %{source_check: check, call: call, answer: line, model_text: model_text, output_decision: decision}}}
    end

    output(result("answer"))
  end

  defp check_revision(nil, current), do: %{decision: :not_found, source_revision: current, projected: nil}

  defp check_revision(record, current) do
    candidate = %{key: record.key, revision: record.value.revision, source_signal_id: record.source_signal_id}
    base = %{source_revision: current, candidate: candidate}

    if candidate.revision == current do
      Map.merge(base, %{decision: :accepted, projected: %{key: record.key, summary: record.value.summary}})
    else
      Map.merge(base, %{decision: :stale_revision, projected: nil})
    end
  end
end

defmodule SupportDesk.BuiltInRevisionAgent do
  @moduledoc false
  use Jido.Agent, name: "built_in_revision_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}

  memory do
    collection :resolutions, max_entries: 4 do
      schema(Joi.object(%{ticket_key: Joi.string(), summary: Joi.string(), revision: Joi.integer()}))
    end
  end

  routes do
    signal_source("/examples/memory/check-source")

    route "examples.memory.source.seed", as: :seed do
      action %{key: key, value: value}, schema: Joi.map(), context: context do
        {:ok, context.agent_state, [Memory.remember(:resolutions, key, value)]}
      end
    end

    route "examples.memory.source.ask", SupportDesk.VerifySourceFlow, as: :ask do
      state(:unchanged)
      reply("examples.memory.source.answer", from: output(:trace))
    end
  end
end

defmodule SupportDesk.ExternalRevisionAgent do
  @moduledoc false
  use Jido.Agent, name: "external_revision_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.Joi

  memory do
    external_collection :resolutions,
      store: {SupportDesk.StaleAdapter, %{name: SupportDesk.AdapterFixture, scope: "support"}} do
      schema(Joi.object(%{ticket_key: Joi.string(), summary: Joi.string(), revision: Joi.integer()}))
    end
  end

  routes do
    signal_source("/examples/memory/check-source")

    route "examples.memory.source.ask", SupportDesk.VerifySourceFlow, as: :ask do
      state(:unchanged)
      reply("examples.memory.source.answer", from: output(:trace))
    end
  end
end

alias Jido.{AgentServer, Signal}
alias Jido.Memory.Store.ETS
alias SupportDesk.{AdapterFixture, BuiltInRevisionAgent, ExternalRevisionAgent, Inference}

fixture = fn model, prompt, _options ->
  %{content: [%{text: "Verified resolution result:\n" <> line}]} = List.last(prompt.messages)
  Inference.fixture_reply(model, prompt, line)
end

key = "T-17"
current = %{ticket_key: key, revision: 2, summary: "Replacement issued after the refund failed."}
stale = %{ticket_key: key, revision: 1, summary: "Refund sent to the original card."}
context = %{source_index: %{key => 2}, inference: Inference.from_args!(System.argv(), fixture)}

agent = BuiltInRevisionAgent.instantiate!(id: "built-in")
seed = BuiltInRevisionAgent.seed_signal!(%{key: key, value: current})
{:ok, agent, [_]} = BuiltInRevisionAgent.cmd(agent, seed)
question = BuiltInRevisionAgent.ask_signal!(%{key: key})
{:ok, _, [%{signal: answer}]} = BuiltInRevisionAgent.cmd(agent, question, context: context)

{:ok, owner} = ETS.start_link(name: AdapterFixture)
{:ok, instance} = Jido.start_link(name: SupportDesk.SourceCheckInstance)

try do
  old = Signal.new!("examples.memory.adapter.seed", %{key: key}, source: "/examples/memory/check-source")
  :ok = ETS.put(AdapterFixture, "support", :resolutions, %{key: key, value: stale, source_signal_id: old.id})
  {:ok, server} = Jido.start_agent(SupportDesk.SourceCheckInstance, ExternalRevisionAgent, id: "external")
  :ok = AgentServer.await_ready(server)
  external_question = ExternalRevisionAgent.ask_signal!(%{key: key})

  {:ok, %{status: :committed, reply: external}} =
    AgentServer.call(server, external_question, context: context, timeout: 120_000)

  trace = %{agent_state: answer.data, external_fixture: external.data}
  json = Jason.encode!(trace, pretty: true)
  IO.puts(json)

  seed_id = seed.id
  stale_id = old.id

  %{source_check: %{decision: :accepted, candidate: %{revision: 2, source_signal_id: ^seed_id}}} = trace.agent_state
  "[T-17] Replacement issued after the refund failed." = String.trim(trace.agent_state.answer)

  %{
    source_check: %{
      decision: :stale_revision,
      candidate: %{revision: 1, source_signal_id: ^stale_id},
      projected: nil,
      source_revision: 2
    }
  } = trace.external_fixture

  "I don't have a verified resolution." = String.trim(trace.external_fixture.answer)
  false = String.contains?(json, stale.summary)
after
  Supervisor.stop(instance)
  GenServer.stop(owner)
end
