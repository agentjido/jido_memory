Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.WakeUpFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "resume_from_mempalace",
    schema: Joi.object(%{case_key: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "wake_up", [key <- input(:case_key), context <- context()] do
      with {:ok, %{snapshot: snapshot}} <- Memory.access(context, :source, :case_history, :snapshot, %{}) do
        count = Map.fetch!(snapshot.metadata, "drawer_count")
        {:ok, %{snapshot: %{case_key: key, namespace: snapshot.namespace, drawer_count: count}}}
      end
    end

    step "open_sources", [snapshot <- result("wake_up", :snapshot), context <- context()] do
      decisions =
        Enum.map(context.handoff.references, fn %{id: id, exchange: index, decision: decision} ->
          source = "T-17.txt#exchange-#{index}"

          case decision do
            :confirmed ->
              {:ok, %{record: record}} = Memory.access(context, :source, :case_history, :open, %{id: id})
              %{"source_file" => "T-17.txt", "exchange_index" => ^index} = record.content
              %{drawer_id: id, source: source, decision: :opened, text: record.text}

            :unconfirmed ->
              %{drawer_id: id, source: source, decision: :withheld}
          end
        end)

      {:ok, %{review: %{snapshot: snapshot, sources: decisions}}}
    end

    step "answer", [review <- result("open_sources", :review), inference <- context(:inference)] do
      excerpts = for %{source: source, text: text} <- review.sources, do: "[#{source}] #{text}"
      pending = Enum.any?(review.sources, &(&1.decision == :withheld))
      action = if pending, do: :ask_for_confirmation, else: :continue_review

      directive = "Case #{review.snapshot.case_key}. Could you confirm your refund instructions before we proceed?"

      {model_text, call} =
        Inference.call!(inference, [
          Context.system("Copy the single sentence after Required question. Output only that sentence."),
          Context.user("Verified passages:\n#{Enum.join(excerpts, "\n")}\nRequired question:\n#{directive}")
        ])

      output = if String.trim(model_text || "") == directive, do: :used_model_question, else: :used_required_question

      {:ok,
       %{
         trace: %{review: review, action: action, answer: directive, model_text: model_text, output: output, call: call}
       }}
    end

    output(result("answer"))
  end
end

defmodule SupportDesk.HandoffAgent do
  @moduledoc false
  use Jido.Agent, name: "wake_up_handoff_agent", plugins: [Jido.Memory.Plugin]

  memory do
    source(:case_history, operations: [snapshot: SupportDesk.PalaceSnapshot, open: SupportDesk.OpenPalaceDrawer])
  end

  routes do
    signal_source("/examples/memory/handoff")

    route "examples.memory.handoff.resume", SupportDesk.WakeUpFlow, as: :resume do
      state(:unchanged)
      reply("examples.memory.handoff.question", from: output(:trace))
    end
  end
end

alias Jido.Memory.MemPalace
alias SupportDesk.{HandoffAgent, Inference}

fixture = fn model, prompt, _options ->
  %{content: [%{text: text}]} = List.last(prompt.messages)
  [_, question] = String.split(text, "\nRequired question:\n")
  Inference.fixture_reply(model, prompt, question)
end

database =
  Path.join(
    System.tmp_dir!(),
    "jido-memory-handoff-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  )

File.mkdir!(database)
palace = [namespace: "case:T-17", backend: :local, backend_opts: [database: Path.join(database, "palace.sqlite3")]]

try do
  {:ok, import} = MemPalace.import_conversations(Path.join(__DIR__, "fixtures"), palace)
  3 = import.accepted_count
  {:ok, snapshot} = MemPalace.wake_up(%{}, palace)
  true = String.contains?(snapshot.essential_story, "refund review")
  true = String.contains?(snapshot.essential_story, "contact preference")

  references =
    Enum.map(import.records, fn %{id: id, content: %{exchange_index: exchange}} ->
      %{id: id, exchange: exchange, decision: if(exchange == 3, do: :unconfirmed, else: :confirmed)}
    end)

  receiver = HandoffAgent.instantiate!(id: "next-shift")
  signal = HandoffAgent.resume_signal!(%{case_key: "T-17"})

  context = %{
    inference: Inference.from_args!(System.argv(), fixture),
    handoff: %{palace: palace, references: references}
  }

  {:ok, _, [%{signal: question}]} = HandoffAgent.cmd(receiver, signal, context: context)

  %{action: :ask_for_confirmation, review: %{snapshot: %{drawer_count: 3}, sources: sources}, call: call} =
    question.data

  [:opened, :opened, :withheld] = Enum.map(sources, & &1.decision)
  %{content: input} = List.last(call.model_input)
  true = String.contains?(input, "[T-17.txt#exchange-1]")
  true = String.contains?(input, "[T-17.txt#exchange-2]")
  false = String.contains?(input, "different card")
  false = String.contains?(input, "#exchange-3")

  IO.puts(
    Jason.encode!(%{agent: receiver.id, import_count: import.accepted_count, handoff: question.data}, pretty: true)
  )
after
  File.rm_rf!(database)
end
