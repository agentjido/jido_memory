Code.require_file("../../support/inference.exs", __DIR__)
Code.require_file("../../00_start_here/00_02_answer_from_memory/agent.exs", __DIR__)

defmodule SupportDesk.CaseIntakeAgent do
  @moduledoc false
  alias Jido.Joi

  use Jido.Agent, name: "case_intake_agent"

  routes do
    signal_source("/examples/memory/escalation")

    route "examples.memory.escalation.receive", as: :receive_case do
      action %{key: key, question: question},
        schema: Joi.object(%{key: Joi.string(), question: Joi.string()}),
        output_schema: Joi.object(%{handoff: Joi.map()}),
        context: context do
        with %{approved: true} = policy <- context.policy,
             %{approved: true, policy_id: id} = procedure <- context.procedure,
             %{id: ^id} <- policy do
          {:ok, %{handoff: %{key: key, question: question, policy: policy, procedure: procedure}}}
        else
          _ -> {:error, :policy_or_procedure_unavailable}
        end
      end

      state(:unchanged)
      reply("examples.memory.escalation.handoff", from: output(:handoff))
    end
  end
end

defmodule SupportDesk.CaseResolver do
  @moduledoc false
  alias Jido.Joi
  alias Jido.Memory.Store.ETS
  alias ReqLLM.Context
  alias SupportDesk.{AnswerFlow, Inference}

  use Jido.Agent, name: "case_resolver", plugins: [Jido.AI.Agent.Plugin, Jido.Memory.Plugin]

  import Jido.AI.Agent.Plugin, only: [ai: 1, reasoning: 2]

  state do
    schema(Joi.object(%{session: Jido.AI.Thread.Projection.schema()}))
  end

  ai do
    reasoning AnswerFlow do
      instructions("Answer in one sentence. Cite the prior ticket, policy, and procedure IDs.")
    end
  end

  memory AnswerFlow do
    external_collection :resolutions,
      store: {ETS, %{name: SupportDesk.HandoffStore, scope: "support"}} do
      schema(Joi.object(%{issue: Joi.string(), summary: Joi.string()}))
    end

    read(:prior_resolutions, collection: :resolutions, filters: [:issue], expose: [:summary], limit: 1)
  end

  routes do
    signal_source("/examples/memory/escalation")

    route "examples.memory.escalation.propose", as: :propose do
      action %{key: key, confirmed_outcome: outcome},
        schema: Joi.object(%{key: Joi.string(), confirmed_outcome: Joi.string()}),
        output_schema: Joi.object(%{proposal: Joi.map()}),
        context: context do
        {reply, call} =
          Inference.call!(context.inference, [
            Context.system("Propose a memory by copying the confirmed case outcome."),
            Context.user("Confirmed outcome:\n#{outcome}")
          ])

        decision = if String.trim(reply || "") == outcome, do: :model_proposed, else: :used_confirmed_outcome

        {:ok,
         %{
           proposal: %{
             key: key,
             proposed: %{issue: "duplicate_charge", summary: outcome},
             model_text: reply,
             decision: decision,
             committed: false,
             model: call,
             source_signal_id: context.signal.id
           }
         }}
      end

      state(:unchanged)
      reply("examples.memory.escalation.proposed", from: output(:proposal))
    end
  end
end

defmodule SupportDesk.EscalationFixture do
  @moduledoc false
  use SupportDesk.Inference.Fixture

  @impl true
  def generate_text(model, prompt, _opts) do
    [record] =
      Enum.find_value(prompt.messages, fn
        %{content: [%{text: "Memory evidence (retrieved records):\n" <> json}]} -> Jason.decode!(json)
        _ -> nil
      end)

    %{"key" => key, "value" => %{"summary" => summary}} = record
    SupportDesk.Inference.fixture_reply(model, prompt, "[#{key}] #{summary} Follow [POL-2] and [PROC-4].")
  end
end

alias Jido.{AgentServer, Session, Signal}
alias Jido.Memory.Store.ETS
alias SupportDesk.{CaseIntakeAgent, CaseResolver, EscalationFixture, HandoffStore, Inference}

fixture = fn model, prompt, _options ->
  %{content: [%{text: "Confirmed outcome:\n" <> result}]} = List.last(prompt.messages)
  Inference.fixture_reply(model, prompt, result)
end

{params, context} = Inference.agent_config!(System.argv(), EscalationFixture)
inference = Inference.from_args!(System.argv(), fixture)
policy = %{id: "POL-2", approved: true, summary: "Refund a confirmed duplicate charge."}

procedure = %{
  id: "PROC-4",
  approved: true,
  policy_id: "POL-2",
  summary: "Verify settlement and send a receipt before closing the case."
}

{:ok, store} = ETS.start_link(name: HandoffStore)
{:ok, instance} = Jido.start_link(name: SupportDesk.EscalationInstance)

try do
  {:ok, intake} = Jido.start_agent(SupportDesk.EscalationInstance, CaseIntakeAgent, id: "intake")
  {:ok, resolver} = Jido.start_agent(SupportDesk.EscalationInstance, CaseResolver, id: "resolver")
  :ok = AgentServer.await_ready(intake)
  :ok = AgentServer.await_ready(resolver)

  prior = Signal.new!("examples.memory.escalation.seeded", %{key: "T-17"}, source: "/examples/memory/escalation")

  record = %{
    key: "T-17",
    value: %{issue: "duplicate_charge", summary: "Refunded the second charge."},
    source_signal_id: prior.id
  }

  :ok = ETS.put(HandoffStore, "support", :resolutions, record)

  ask = fn key, session ->
    request = CaseIntakeAgent.receive_case_signal!(%{key: key, question: "How should we handle this duplicate charge?"})

    {:ok, %{status: :committed, reply: handoff}} =
      AgentServer.call(intake, request, context: %{policy: policy, procedure: procedure})

    %{policy: %{id: "POL-2"}, procedure: %{id: "PROC-4", policy_id: "POL-2"}} = handoff.data

    prompt =
      "Case #{key}. #{handoff.data.question}\nApproved policy [POL-2]: #{policy.summary}\n" <>
        "Approved procedure [PROC-4]: #{procedure.summary}"

    signal = CaseResolver.request_signal!(Map.put(params, :input, prompt))

    {:ok, %{status: :committed, reply: reply}} =
      AgentServer.call(resolver, signal, context: Map.put(context, :jido_ai_session, session), timeout: 120_000)

    %{status: status, memory_trace: trace, output: model_text} = reply.data
    true = status in [:completed, :blocked]
    [reference] = trace.recall.records
    citations = [reference.key, "POL-2", "PROC-4"]
    supported = is_binary(model_text) && Enum.all?(citations, &String.contains?(model_text, &1))
    verified = "Apply [POL-2] and [PROC-4]. See the prior case [#{reference.key}]."

    %{
      case: key,
      handoff_signal_id: handoff.id,
      session_id: session.id,
      memory: trace,
      model_text: model_text,
      model_status: status,
      model_reason: reply.data[:reason],
      answer: if(supported, do: model_text, else: verified)
    }
  end

  first = ask.("T-18", Session.new(id: "shift-one"))
  prior_id = prior.id
  %{recall: %{records: [%{key: "T-17", source_signal_id: ^prior_id}]}} = first.memory

  outcome = "Refunded a confirmed duplicate and sent receipt R-18."
  propose = CaseResolver.propose_signal!(%{key: "T-18", confirmed_outcome: outcome})
  {:ok, %{reply: proposal}} = AgentServer.call(resolver, propose, context: %{inference: inference}, timeout: 120_000)
  %{key: "T-18", proposed: %{summary: ^outcome} = approved, committed: false} = proposal.data
  {:ok, [%{key: "T-17"}]} = ETS.recall(%{name: HandoffStore, scope: "support"}, :resolutions, %{}, 4, %{})

  approve =
    Signal.new!("examples.memory.escalation.approved", %{proposal_id: propose.id},
      source: "/examples/memory/escalation"
    )

  :ok = ETS.put(HandoffStore, "support", :resolutions, %{key: "T-18", value: approved, source_signal_id: approve.id})

  next_case = ask.("T-19", Session.new(id: "shift-two"))
  approval_id = approve.id
  %{recall: %{records: [%{key: "T-18", source_signal_id: ^approval_id}]}} = next_case.memory
  false = Enum.any?(first.memory.model_input, &String.contains?(&1.content, "receipt R-18"))
  true = Enum.any?(next_case.memory.model_input, &String.contains?(&1.content, "receipt R-18"))

  IO.puts(
    Jason.encode!(
      %{
        first_case: first,
        proposal: proposal.data,
        approval: %{signal_id: approve.id, decision: :committed},
        next_case: next_case
      },
      pretty: true
    )
  )
after
  Supervisor.stop(instance)
  GenServer.stop(store)
end
