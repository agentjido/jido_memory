defmodule SupportDesk.AnswerAfterTimeout do
  @moduledoc false
  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "policy_timeout_flow",
    schema: Joi.object(%{}),
    output_schema: Joi.object(%{trace: Joi.map()})

  @timeout_ms 25
  @defer "I need the current policy before I can recommend a refund."

  flow do
    parallel "sources" do
      action "history", memory <- context() do
        with {:ok, [record]} <- Memory.recall(memory, :resolutions, where: %{issue: "duplicate_charge"}, limit: 1) do
          {:ok, %{record: record, status: :ok}}
        end
      end

      action "policy", [] do
        attempts = Enum.map(1..2, &fetch_policy/1)
        {:ok, %{status: :unavailable, attempts: attempts}}
      end
    end

    step "respond", [sources <- result("sources"), inference <- context(:inference)] do
      [%{value: %{record: record}}, %{value: %{status: :unavailable}}] = sources
      excerpt = "[#{record.key}] #{record.value.summary}"

      messages = [
        Context.system("Copy the verified claim verbatim for the customer. Output only that line."),
        Context.user("Verified claim:\n#{excerpt}")
      ]

      {model_text, call} = Inference.call!(inference, messages)
      report = String.trim(model_text || "")

      {history, decision} =
        if report == excerpt, do: {report, :accepted_history}, else: {excerpt, :used_history_excerpt}

      {:ok,
       %{
         sources: sources,
         model: %{text: model_text, call: call, decision: decision},
         recommendation: %{status: :deferred, reason: :policy_unavailable},
         answer: "#{history}\n#{@defer}"
       }}
    end

    output(%{trace: result("respond")})
  end

  defp fetch_policy(attempt) do
    # The synthetic source never replies. The deadline cancels each request.
    request = Task.async(fn -> Process.sleep(:infinity) end)
    nil = Task.yield(request, @timeout_ms) || Task.shutdown(request, :brutal_kill)
    %{attempt: attempt, status: :timeout, timeout_ms: @timeout_ms}
  end
end

defmodule SupportDesk.PolicyTimeoutAgent do
  @moduledoc false
  use Jido.Agent, name: "policy_timeout_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}

  memory do
    collection :resolutions, max_entries: 3 do
      schema(Joi.object(%{issue: Joi.string(), summary: Joi.string()}))
    end
  end

  routes do
    signal_source("/examples/memory/01_03_answer_after_timeout")

    route "examples.memory.ticket.resolved", as: :resolve do
      action %{key: key, value: value},
        schema: Joi.object(%{key: Joi.string(), value: Joi.map()}),
        context: context do
        {:ok, context.agent_state, [Memory.remember(:resolutions, key, value)]}
      end
    end

    route "examples.memory.policy.check", SupportDesk.AnswerAfterTimeout, as: :ask do
      state(:unchanged)
      reply("examples.memory.policy.check.answered", from: output(:trace))
    end
  end
end
