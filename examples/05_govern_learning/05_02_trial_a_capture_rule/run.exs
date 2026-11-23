Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.ShadowCaptureFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}

  use Jido.Flow,
    name: "shadow_capture",
    schema:
      Joi.object(%{key: Joi.string(), status: Joi.string(), summary: Joi.string(), verified_reason: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "active_rule", [status <- input(:status), summary <- input(:summary)] do
      {:ok, %{record: if(status == "confirmed", do: %{summary: summary})}}
    end

    step "shadow_rule", [status <- input(:status), summary <- input(:summary), reason <- input(:verified_reason)] do
      {:ok, %{record: if(status == "confirmed", do: %{summary: summary, verified_reason: reason})}}
    end

    step "record_decision", [
      key <- input(:key),
      active <- result("active_rule", :record),
      shadow <- result("shadow_rule", :record),
      signal <- context(:signal)
    ] do
      directives = if active, do: [Memory.remember(:resolutions, key, active)], else: []

      {:ok,
       %{
         trace: %{
           key: key,
           source_signal_id: signal.id,
           active_fields: active,
           shadow_fields: shadow,
           active_commits: length(directives),
           shadow_commits: 0
         }
       }, directives}
    end

    output(result("record_decision"))
  end
end

defmodule SupportDesk.CompareCaptureFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "compare_capture_rules",
    schema: Joi.object(%{key: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "recall", key <- input(:key), inline: [context: context] do
      {:ok, [%{key: ^key, value: record}]} = Memory.recall(context, :resolutions, limit: 1)
      {:ok, %{record: record}}
    end

    step "compare", [
      record <- result("recall", :record),
      key <- input(:key),
      inference <- context(:inference),
      shadow <- context(:shadow_preview)
    ] do
      %{key: ^key, shadow_commits: 0, shadow_fields: preview} = shadow
      reason = Map.fetch!(preview, :verified_reason)

      results =
        for {mode, value} <- [active: record, shadow: preview], into: %{} do
          text = "[#{key}] #{value.summary}\nVerified reason: #{Map.get(value, :verified_reason, "unknown")}"

          {reply, call} =
            Inference.call!(inference, [
              Context.system("Answer with the reason given in the evidence. When it is unknown, say Unknown."),
              Context.user("Why was the refund issued?\nEvidence:\n#{text}")
            ])

          supported = value[:verified_reason] == reason
          answered = is_binary(reply) && String.contains?(String.downcase(reply), String.downcase(reason))

          {mode,
           %{
             call: call,
             model_text: reply,
             evidence_supports_answer: supported,
             model_gave_expected_reason: answered,
             supported_answer: supported && answered
           }}
        end

      {:ok, %{trace: results}}
    end

    output(result("compare"))
  end
end

defmodule SupportDesk.ShadowAgent do
  @moduledoc false
  use Jido.Agent, name: "shadow_agent", plugins: [Jido.Memory.Plugin]

  memory do
    collection :resolutions, max_entries: 4 do
      schema(Jido.Joi.object(%{summary: Jido.Joi.string()}))
    end
  end

  routes do
    signal_source("/examples/memory/shadow")

    route "examples.memory.shadow.closed", SupportDesk.ShadowCaptureFlow, as: :capture do
      state(:unchanged)
      reply("examples.memory.shadow.captured", from: output(:trace))
    end

    route "examples.memory.shadow.compare", SupportDesk.CompareCaptureFlow, as: :compare do
      state(:unchanged)
      reply("examples.memory.shadow.compared", from: output(:trace))
    end
  end
end

alias Jido.Memory
alias SupportDesk.{Inference, ShadowAgent}

fixture = fn model, prompt, _options ->
  %{content: [%{text: text}]} = List.last(prompt.messages)
  [_, reason] = String.split(text, "\nVerified reason: ")
  Inference.fixture_reply(model, prompt, reason)
end

agent = ShadowAgent.instantiate!(id: "capture-trial")

confirmed =
  ShadowAgent.capture_signal!(%{
    key: "T-17",
    status: "confirmed",
    summary: "Refunded USD 30.",
    verified_reason: "duplicate settlement"
  })

unconfirmed =
  ShadowAgent.capture_signal!(%{
    key: "T-18",
    status: "pending",
    summary: "Refund requested.",
    verified_reason: "agent hypothesis"
  })

{:ok, agent, [%Jido.Memory.Directive.Remember{}, %Jido.Agent.Directive.Reply{signal: capture}]} =
  ShadowAgent.cmd(agent, confirmed)

{:ok, agent, [%{signal: skipped}]} = ShadowAgent.cmd(agent, unconfirmed)
%{active_commits: 1, shadow_commits: 0, shadow_fields: %{verified_reason: "duplicate settlement"}} = capture.data
%{active_commits: 0, shadow_commits: 0, active_fields: nil, shadow_fields: nil} = skipped.data

option = %{inference: Inference.from_args!(System.argv(), fixture), shadow_preview: capture.data}
question = ShadowAgent.compare_signal!(%{key: "T-17"})
{:ok, agent, [%{signal: comparison}]} = ShadowAgent.cmd(agent, question, context: option)

%{active: active, shadow: shadow} = comparison.data
false = active.evidence_supports_answer
true = shadow.evidence_supports_answer
%{content: active_input} = List.last(active.call.model_input)
%{content: shadow_input} = List.last(shadow.call.model_input)
false = String.contains?(active_input, "duplicate settlement")
true = String.contains?(shadow_input, "duplicate settlement")
source = confirmed.id

{:ok, [%{key: "T-17", source_signal_id: ^source, value: %{summary: "Refunded USD 30."} = saved}]} =
  Memory.recall(agent, :resolutions)

false = Map.has_key?(saved, :verified_reason)

IO.puts(
  Jason.encode!(%{confirmed: capture.data, pending: skipped.data, comparison: comparison.data, stored: saved},
    pretty: true
  )
)
