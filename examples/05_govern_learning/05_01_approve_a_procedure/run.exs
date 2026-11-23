Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.Procedure do
  @moduledoc false

  alias Jido.Joi

  def schema do
    Joi.object(%{revision: Joi.integer(), requires_policy: Joi.boolean(), summary: Joi.string()})
  end

  def draft(revision, requires_policy) do
    summary =
      if requires_policy,
        do: "Refund a confirmed duplicate only when current policy permits it. If policy is missing, ask for it.",
        else: "Refund a confirmed duplicate if policy is missing or permits it."

    %{revision: revision, requires_policy: requires_policy, summary: summary}
  end

  def replay(procedure, cases) do
    for scenario <- cases do
      actual = decide(procedure, scenario)
      %{case_id: scenario.id, expected: scenario.expected, actual: actual, passed: actual == scenario.expected}
    end
  end

  def decide(_procedure, %{duplicate: false}), do: :decline
  def decide(_procedure, %{policy: :forbids}), do: :decline
  def decide(%{requires_policy: true}, %{policy: :unknown}), do: :ask_for_policy
  def decide(_procedure, %{duplicate: true}), do: :refund
end

defmodule SupportDesk.DraftProcedureFlow do
  @moduledoc false

  alias Jido.Joi
  alias ReqLLM.Context
  alias SupportDesk.{Inference, Procedure}

  use Jido.Flow,
    name: "draft_procedure",
    schema: Joi.object(%{history: Joi.list(Joi.map())}),
    output_schema: Joi.object(%{state: Joi.map(), trace: Joi.map()})

  flow do
    step "propose", [history <- input(:history), inference <- context(:inference)] do
      {raw, call} =
        Inference.call!(inference, [
          Context.system(
            "Use the outcomes to decide whether the procedure requires a policy check. " <>
              "Output only true if a case required a policy check, or false if none did."
          ),
          Context.user("Case outcomes:\n" <> Jason.encode!(history))
        ])

      {rule, decision} =
        case Jason.decode(String.trim(raw || "")) do
          {:ok, flag} when is_boolean(flag) -> {Procedure.draft(1, flag), :model_proposal}
          {:ok, %{"require_policy" => flag}} when is_boolean(flag) -> {Procedure.draft(1, flag), :model_proposal}
          _ -> {Procedure.draft(1, false), :example_baseline}
        end

      {:ok, %{rule: rule, proposal: %{call: call, raw: raw, decision: decision}}}
    end

    step "replay", [draft <- result("propose"), tests <- context(:cases), state <- context(:agent_state)] do
      results = Procedure.replay(draft.rule, tests)

      {:ok,
       %{
         state: %{state | pending: draft.rule},
         trace: %{candidate: draft.rule, replay: results, proposed: draft.proposal}
       }}
    end

    output(result("replay"))
  end
end

defmodule SupportDesk.FollowProcedureFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.{Inference, Procedure}

  use Jido.Flow,
    name: "follow_approved_procedure",
    schema:
      Joi.object(%{case_id: Joi.string(), duplicate: Joi.boolean(), policy: Joi.enum([:allows, :forbids, :unknown])}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "recall", [], inline: [context: context] do
      with {:ok, records} <- Memory.recall(context, :procedures, limit: 1) do
        {:ok, %{record: List.first(records)}}
      end
    end

    step "answer", [
      record <- result("recall", :record),
      id <- input(:case_id),
      duplicate <- input(:duplicate),
      policy <- input(:policy),
      inference <- context(:inference)
    ] do
      result =
        case record do
          nil ->
            %{decision: :no_approved_procedure, line: "No approved procedure."}

          %{key: key, value: value} ->
            decision = Procedure.decide(value, %{duplicate: duplicate, policy: policy})
            %{decision: decision, line: "[#{key} v#{value.revision}] #{value.summary} Next action: #{decision}."}
        end

      {reply, call} =
        Inference.call!(inference, [
          Context.system("Use the approved procedure to tell the operator what to do. Include the version."),
          Context.user("Case #{id}.\nApproved result:\n#{result.line}")
        ])

      {:ok, %{trace: %{record: record, decision: result.decision, answer: result.line, model_text: reply, call: call}}}
    end

    output(result("answer"))
  end
end

defmodule SupportDesk.ProcedureAgent do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias SupportDesk.Procedure

  use Jido.Agent, name: "procedure_agent", plugins: [Jido.Memory.Plugin]

  state do
    schema(Joi.object(%{pending: Joi.map() |> Joi.default(%{})}))
  end

  memory do
    collection :procedures, max_entries: 4 do
      schema(Procedure.schema())
    end
  end

  routes do
    signal_source("/examples/memory/procedure")

    route "examples.memory.procedure.propose", SupportDesk.DraftProcedureFlow, as: :propose do
      state(from: output(:state))
      reply("examples.memory.procedure.proposed", from: output(:trace))
    end

    route "examples.memory.procedure.review", as: :review do
      action %{revision: revision, operation: operation},
        schema: Joi.object(%{revision: Joi.integer(), operation: Joi.enum([:correct, :approve])}),
        output_schema: Joi.object(%{state: Joi.map(), trace: Joi.map()}),
        context: context do
        review(context, revision, operation)
      end

      state(from: output(:state))
      reply("examples.memory.procedure.reviewed", from: output(:trace))
    end

    route "examples.memory.procedure.follow", SupportDesk.FollowProcedureFlow, as: :follow do
      state(:unchanged)
      reply("examples.memory.procedure.action", from: output(:trace))
    end
  end

  defp review(
         %{agent_state: %{pending: %{revision: revision}} = state, role: :operator, cases: cases},
         revision,
         :correct
       ) do
    corrected = Procedure.draft(revision + 1, true)
    result = %{decision: :corrected, revision: corrected.revision, replay: Procedure.replay(corrected, cases)}
    {:ok, %{state: %{state | pending: corrected}, trace: result}}
  end

  defp review(
         %{agent_state: %{pending: %{revision: revision} = procedure} = state, role: :operator, cases: cases},
         revision,
         :approve
       ) do
    replay = Procedure.replay(procedure, cases)

    if Enum.all?(replay, & &1.passed) do
      {:ok, %{state: %{state | pending: %{}}, trace: %{decision: :approved, revision: revision, replay: replay}},
       [Memory.remember(:procedures, "duplicate-charge", procedure)]}
    else
      {:ok, %{state: state, trace: %{decision: :regression, revision: revision, replay: replay}}}
    end
  end

  defp review(%{agent_state: state}, revision, _operation) do
    {:ok, %{state: state, trace: %{decision: :not_approved, revision: revision}}}
  end
end

alias SupportDesk.{Inference, ProcedureAgent}

fixture = fn model, prompt, _options ->
  %{content: [%{text: text}]} = List.last(prompt.messages)

  answer =
    case text do
      "Case outcomes:\n" <> _ -> ~s({"require_policy":false})
      _ -> List.last(String.split(text, "\nApproved result:\n"))
    end

  Inference.fixture_reply(model, prompt, answer)
end

history = [
  %{id: "T-10", duplicate: true, outcome: "Refund succeeded"},
  %{id: "T-11", duplicate: false, outcome: "Refund refused"}
]

cases = [
  %{id: "T-10", duplicate: true, policy: :allows, expected: :refund},
  %{id: "T-11", duplicate: false, policy: :allows, expected: :decline},
  %{id: "T-17", duplicate: true, policy: :unknown, expected: :ask_for_policy}
]

context = %{inference: Inference.from_args!(System.argv(), fixture), role: :operator, cases: cases}
agent = ProcedureAgent.instantiate!(id: "procedure-editor")

dispatch = fn agent, signal ->
  {:ok, next, directives} = ProcedureAgent.cmd(agent, signal, context: context)
  [%{signal: reply}] = Enum.filter(directives, &match?(%Jido.Agent.Directive.Reply{}, &1))
  {next, reply.data}
end

review = fn revision, operation -> ProcedureAgent.review_signal!(%{revision: revision, operation: operation}) end
follow = ProcedureAgent.follow_signal!(%{case_id: "T-18", duplicate: true, policy: :unknown})

{agent, draft} = dispatch.(agent, ProcedureAgent.propose_signal!(%{history: history}))
{agent, rejected} = dispatch.(agent, review.(1, :approve))
{agent, early} = dispatch.(agent, follow)
{agent, corrected} = dispatch.(agent, review.(1, :correct))
{agent, approved} = dispatch.(agent, review.(2, :approve))
{_agent, later} = dispatch.(agent, follow)

%{candidate: %{revision: 1}, replay: [_, _, %{case_id: "T-17", actual: :refund, passed: false}]} = draft
%{decision: :regression} = rejected
%{decision: :no_approved_procedure, record: nil} = early
%{decision: :corrected, revision: 2} = corrected
true = Enum.all?(corrected.replay, & &1.passed)
%{decision: :approved, revision: 2} = approved
%{decision: :ask_for_policy, record: %{source_signal_id: source, value: %{revision: 2}}} = later
true = is_binary(source)
%{content: input} = List.last(later.call.model_input)
true = String.contains?(input, "[duplicate-charge v2]")
false = String.contains?(input, draft.candidate.summary)

IO.puts(
  Jason.encode!(
    %{
      draft: draft,
      rejected: rejected,
      before_approval: early,
      corrected: corrected,
      approved: approved,
      after_approval: later
    },
    pretty: true
  )
)
