defmodule SupportDesk.AnswerFlow do
  @moduledoc false

  alias Jido.AI.Reasoning.Actions.{
    CallModel,
    FinalizeTurn,
    GuardOutput,
    ProjectConversation,
    RecordModelAttempt,
    StartRequest
  }

  alias Jido.AI.Reasoning.Result
  alias Jido.Joi
  alias Jido.Memory.Actions.RecallForModel

  @flow_id "examples/support/answer-from-memory"
  use Jido.Flow,
    id: @flow_id,
    name: "answer_from_memory",
    schema:
      Joi.object(%{
        input: Joi.string(),
        instructions: Joi.string(),
        model: Joi.any(),
        options: Joi.map() |> Joi.default(%{}),
        where: Joi.map() |> Joi.default(%{issue: "duplicate_charge"}),
        recall: Joi.boolean() |> Joi.default(true)
      }),
    output_schema: Joi.object(%{state: Joi.map(), response: Joi.map()})

  flow do
    step("start",
      action: StartRequest,
      params: %{
        flow: %{id: "examples/support/answer-from-memory", vsn: 1},
        input: input(:input),
        instructions: input(:instructions),
        model: input(:model),
        options: input(:options),
        context_window: %{max_messages: 8, max_bytes: 8_000},
        max_model_calls: 1
      }
    )

    step("project", action: ProjectConversation, params: %{turn: result("start")})

    step("recall",
      action: RecallForModel,
      params: %{
        context: result("project", :context),
        grant: :prior_resolutions,
        where: input(:where),
        enabled: input(:recall)
      }
    )

    step("model",
      action: CallModel,
      params: %{turn: result("project", :turn), context: result("recall", :context), tools: false}
    )

    step("check_output",
      action: GuardOutput,
      params: %{turn: result("model", :turn), outcome: result("model", :outcome)}
    )

    step("record",
      action: RecordModelAttempt,
      params: %{
        turn: result("model", :turn),
        context: result("model", :context),
        outcome: result("model", :outcome),
        output_allowed: result("check_output", :allowed),
        output_reason: result("check_output", :reason)
      }
    )

    step "outcome", turn <- result("record", :turn) do
      {:ok, %{turn: turn, result: result_for(turn)}}
    end

    step("finalize", action: FinalizeTurn, params: %{outcome: result("outcome")})

    step "trace",
         [final <- result("finalize"), model <- result("model", :context), recall <- result("recall", :recall)] do
      messages =
        Enum.map(model.request.context.messages, fn message ->
          %{role: message.role, content: Enum.map_join(message.content, & &1.text)}
        end)

      trace = %{recall: recall, model_input: messages, request_digest: model.digest}
      {:ok, put_in(final, [:response, :memory_trace], trace)}
    end

    output(result("trace"))
  end

  defp result_for(%{output_allowed: true, model_outcome: %{status: :ok, text: text}}), do: Result.completed(text)
  defp result_for(%{output_allowed: false, output_reason: reason}), do: Result.blocked(:output, reason)
  defp result_for(%{model_outcome: %{reason: reason}}), do: Result.failed(:model, reason)
end

defmodule SupportDesk.MemoryFixture do
  @moduledoc false
  @behaviour Jido.AI.InferenceClient

  alias ReqLLM.{Context, Response}

  @impl true
  def generate_text(model, prompt, _options) do
    records =
      Enum.find_value(prompt.messages, [], fn
        %{role: :user, content: [%{text: "Memory evidence (retrieved records):\n" <> json}]} ->
          Jason.decode!(json)

        _ ->
          nil
      end)

    answer =
      case records do
        [%{"key" => key, "value" => %{"summary" => summary}}] -> "[#{key}] #{summary}"
        [] -> "I don't have a prior resolution in memory."
      end

    {:ok,
     %Response{
       id: "fixture",
       model: model,
       context: prompt,
       message: Context.assistant(answer),
       finish_reason: :stop
     }}
  end

  @impl true
  def evaluation_models, do: []

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks),
      {name, arity} not in [generate_text: 3, evaluation_models: 0] do
    @impl true
    def unquote(name)(unquote_splicing(Macro.generate_arguments(arity, __MODULE__))), do: {:error, :not_supported}
  end
end

defmodule SupportDesk.MemoryAgent do
  @moduledoc false
  use Jido.Agent, name: "support_memory_agent", plugins: [Jido.AI.Agent.Plugin, Jido.Memory.Plugin]

  import Jido.AI.Agent.Plugin, only: [ai: 1, reasoning: 2]

  alias Jido.{Joi, Memory}

  state do
    schema(Joi.object(%{session: Jido.AI.Thread.Projection.schema()}))
  end

  ai do
    reasoning SupportDesk.AnswerFlow do
      instructions("""
      If there is no message labeled Memory evidence, reply exactly: I don't have a prior resolution in memory.
      Otherwise, answer in one short sentence using that evidence and cite the ticket key.
      """)
    end
  end

  memory SupportDesk.AnswerFlow do
    collection :resolutions, max_entries: 3 do
      schema(Joi.object(%{issue: Joi.string(), summary: Joi.string(), internal_note: Joi.string()}))
    end

    read(:prior_resolutions, collection: :resolutions, filters: [:issue], expose: [:summary], limit: 1)
  end

  routes do
    signal_source("/examples/memory/answer")

    route "examples.memory.ticket.resolved", as: :resolve do
      action %{key: key, value: value}, schema: Joi.map(), context: context do
        {:ok, context.agent_state, [Memory.remember(:resolutions, key, value)]}
      end
    end
  end
end
