defmodule SupportDesk.FitAndCheckEvidence do
  @moduledoc false

  alias Jido.AI.Context, as: ModelContext

  alias Jido.AI.Reasoning.Actions.{
    CallModel,
    FinalizeTurn,
    ProjectConversation,
    RecordModelAttempt,
    StartRequest
  }

  alias Jido.AI.Reasoning.Result
  alias Jido.AI.Thread.Projection
  alias Jido.{Joi, Session}
  alias Jido.Memory.Actions.RecallGranted
  alias ReqLLM.Context
  alias SupportDesk.Inference

  @budget_bytes 40
  @proposals "Proposed claims:\n[T-17] Refunded the second charge\n[T-17] Waived the late fee"
  @revision_instructions "Copy the verified claim verbatim for the customer. Output only that line."

  use Jido.Flow,
    id: "examples/support/fit-and-check-evidence",
    name: "fit_and_check_evidence",
    schema:
      Joi.object(%{
        input: Joi.string(),
        instructions: Joi.string(),
        model: Joi.any(),
        options: Joi.map() |> Joi.default(%{})
      }),
    output_schema: Joi.object(%{state: Joi.map(), response: Joi.map()})

  flow do
    step("start",
      action: StartRequest,
      params: %{
        flow: %{id: "examples/support/fit-and-check-evidence", vsn: 1},
        input: input(:input),
        instructions: input(:instructions),
        model: input(:model),
        options: input(:options),
        context_window: %{max_messages: 8, max_bytes: 8_000},
        max_model_calls: 2
      }
    )

    step("project", action: ProjectConversation, params: %{turn: result("start")})

    step("recall",
      action: RecallGranted,
      params: %{
        grant: :prior_resolutions,
        where: %{issue: "duplicate_charge"}
      }
    )

    step "fit", [recall <- result("recall", :recall), model_context <- result("project", :context)] do
      evidence = fit(recall.records)
      excerpts = Enum.map_join(evidence.selected, "\n", & &1.excerpt)

      with {:ok, prompt} <-
             ModelContext.transform(model_context, "example:fit-evidence", fn prompt ->
               Context.append(prompt, Context.user("Memory evidence:\n#{excerpts}\n\n#{@proposals}"))
             end) do
        {:ok, %{context: prompt, evidence: Map.put(evidence, :grant_decision, recall.decision)}}
      end
    end

    step("draft",
      action: CallModel,
      params: %{turn: result("project", :turn), context: result("fit", :context), tools: false}
    )

    step "check_claims", [draft <- result("draft", :outcome), evidence <- result("fit", :evidence)] do
      check_claims(draft, evidence)
    end

    step("record_draft",
      action: RecordModelAttempt,
      params: %{
        turn: result("draft", :turn),
        context: result("draft", :context),
        outcome: result("draft", :outcome),
        output_allowed: true,
        output_reason: nil,
        persist_message: false
      }
    )

    step "revision_context", check <- result("check_claims") do
      prompt =
        Context.new([
          Context.system(@revision_instructions),
          Context.user("Verified claim:\n#{check.verified}")
        ])

      with {:ok, model_context} <- ModelContext.new(prompt) do
        {:ok, %{context: model_context}}
      end
    end

    step("revise",
      action: CallModel,
      params: %{turn: result("record_draft", :turn), context: result("revision_context", :context), tools: false}
    )

    step "check_revision", [revision <- result("revise", :outcome), check <- result("check_claims")] do
      accepted = revision.status == :ok and String.trim(revision[:text] || "") == check.verified
      decision = if accepted, do: :accepted_revision, else: :used_verified_excerpt
      {:ok, %{accepted: accepted, decision: decision, text: check.verified, model_text: revision[:text]}}
    end

    step("record_revision",
      action: RecordModelAttempt,
      params: %{
        turn: result("revise", :turn),
        context: result("revise", :context),
        outcome: result("revise", :outcome),
        output_allowed: result("check_revision", :accepted),
        output_reason: nil,
        persist_message: result("check_revision", :accepted)
      }
    )

    step "outcome", [turn <- result("record_revision", :turn), answer <- result("check_revision")] do
      with {:ok, turn} <- retain_answer(turn, answer) do
        {:ok, %{turn: turn, result: Result.completed(answer.text)}}
      end
    end

    step("finalize", action: FinalizeTurn, params: %{outcome: result("outcome")})

    step "trace",
         [
           final <- result("finalize"),
           evidence <- result("fit", :evidence),
           draft <- result("draft"),
           check <- result("check_claims"),
           revision <- result("revise"),
           answer <- result("check_revision")
         ] do
      trace = %{
        evidence: evidence,
        draft: %{
          text: draft.outcome.text,
          verified: [check.verified],
          rejected: check.rejected,
          call: call_trace(draft)
        },
        answer: answer |> Map.delete(:accepted) |> Map.put(:call, call_trace(revision))
      }

      {:ok, put_in(final, [:response, :memory_trace], trace)}
    end

    output(result("trace"))
  end

  defp fit(records) do
    {selected, excluded, used_bytes} =
      Enum.reduce(records, {[], [], 0}, fn record, {selected, excluded, used_bytes} ->
        excerpt = "[#{record.key}] #{record.value.summary}"
        bytes = byte_size(excerpt) + if(selected == [], do: 0, else: 1)

        if used_bytes + bytes <= @budget_bytes do
          entry = %{key: record.key, source_signal_id: record.source_signal_id, excerpt: excerpt}
          {[entry | selected], excluded, used_bytes + bytes}
        else
          {selected, [%{key: record.key, reason: :evidence_budget} | excluded], used_bytes}
        end
      end)

    %{
      budget_bytes: @budget_bytes,
      used_bytes: used_bytes,
      selected: Enum.reverse(selected),
      excluded: Enum.reverse(excluded)
    }
  end

  defp check_claims(%{status: :ok, text: text}, evidence) do
    excerpts = Enum.map(evidence.selected, & &1.excerpt)
    clauses = text |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)

    case Enum.split_with(clauses, &(&1 in excerpts)) do
      {[verified], rejected} -> {:ok, %{verified: verified, rejected: rejected}}
      _ -> {:error, :expected_one_verified_claim}
    end
  end

  defp check_claims(draft, _evidence), do: {:error, draft[:reason] || :draft_failed}

  defp retain_answer(turn, %{accepted: true}), do: {:ok, turn}

  defp retain_answer(turn, %{text: text}) do
    refs = %{request_id: turn.request_id, run_id: turn.run_id}
    session = Session.decode!(turn.session)

    with {:ok, updated} <-
           Projection.append(session, %{role: :assistant, content: text}, refs, System.system_time(:millisecond)),
         {:ok, document} <- Session.encode_for_runic(updated) do
      {:ok, %{turn | session: document}}
    end
  end

  defp call_trace(%{context: context, outcome: outcome}) do
    context
    |> Inference.prepared_trace()
    |> Map.merge(Map.take(outcome, [:status, :finish_reason, :usage]))
  end
end

defmodule SupportDesk.FitEvidenceFixture do
  @moduledoc false
  use SupportDesk.Inference.Fixture

  @impl true
  def generate_text(model, prompt, _options) do
    %{role: :user, content: [%{text: text}]} = List.last(prompt.messages)

    answer =
      text
      |> String.split("\n\nProposed claims:\n")
      |> List.last()
      |> String.replace_prefix("Verified claim:\n", "")

    SupportDesk.Inference.fixture_reply(model, prompt, answer)
  end
end

defmodule SupportDesk.FitEvidenceAgent do
  @moduledoc false
  use Jido.Agent, name: "fit_evidence_agent", plugins: [Jido.AI.Agent.Plugin, Jido.Memory.Plugin]

  import Jido.AI.Agent.Plugin, only: [ai: 1, reasoning: 2]

  alias Jido.{Joi, Memory}

  state do
    schema(Joi.object(%{session: Jido.AI.Thread.Projection.schema()}))
  end

  ai do
    reasoning SupportDesk.FitAndCheckEvidence do
      instructions(
        "Copy the proposed claims verbatim, one per line, for a separate evidence check. Output only the proposed claims."
      )
    end
  end

  memory SupportDesk.FitAndCheckEvidence do
    collection :resolutions, max_entries: 3 do
      schema(Joi.object(%{issue: Joi.string(), summary: Joi.string()}))
    end

    read(:prior_resolutions, collection: :resolutions, filters: [:issue], expose: [:summary], limit: 3)
  end

  routes do
    signal_source("/examples/memory/fit-evidence")

    route "examples.memory.ticket.resolved", as: :resolve do
      action %{key: key, value: value}, schema: Joi.map(), context: context do
        {:ok, context.agent_state, [Memory.remember(:resolutions, key, value)]}
      end
    end
  end
end
