Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.NavigatePalaceFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "navigate_project_memory",
    schema: Joi.object(%{question: Joi.string(), term: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "look_at_taxonomy", [term <- input(:term), context <- context()] do
      {:ok, taxonomy} = Memory.access(context, :source, :project, :taxonomy, %{})
      {:ok, result} = Memory.access(context, :source, :project, :search, %{term: term})
      {:ok, %{wings: taxonomy.wings, broad_hits: Enum.map(result.hits, &reference/1)}}
    end

    step "filter_room", [observed <- result("look_at_taxonomy"), term <- input(:term), context <- context()] do
      # The case was routed to billing by the host.
      [%{name: wing, halls: halls}] = observed.wings
      hall = Enum.find(halls, fn hall -> Enum.any?(hall.rooms, &(&1.name == "billing")) end)
      filter = %{"wing" => wing, "hall" => hall.name, "room" => "billing"}
      {:ok, result} = Memory.access(context, :source, :project, :search, %{term: term, placement: filter})
      [hit | _] = result.hits
      narrowed = Enum.map(result.hits, &reference/1)

      {:ok,
       %{
         navigation: Map.merge(observed, %{filter: filter, narrowed_hits: narrowed, selected: reference(hit)}),
         excerpt: hit.record.text
       }}
    end

    step "answer", [room <- result("filter_room"), question <- input(:question), inference <- context(:inference)] do
      evidence = "[#{room.navigation.selected.path}] #{room.excerpt}"

      {reply, call} =
        Inference.call!(inference, [
          Context.system("Answer using the selected passage. Include its source citation."),
          Context.user("Question: #{question}\nSelected passage:\n#{evidence}")
        ])

      allowed =
        is_binary(reply) && String.contains?(reply, "REFUND_RECEIPT") &&
          String.contains?(reply, room.navigation.selected.path) && !String.contains?(reply, "LOGIN_CHALLENGE")

      answer = if allowed, do: reply, else: evidence

      {:ok, %{trace: %{navigation: room.navigation, call: call, model_text: reply, answer: answer}}}
    end

    output(result("answer"))
  end

  defp reference(hit) do
    %{record: record, extensions: %{"mempalace" => placement}} = hit
    %{id: record.id, path: record.content["source_file"], placement: placement}
  end
end

defmodule SupportDesk.ProjectPalaceAgent do
  @moduledoc false
  use Jido.Agent, name: "project_palace_agent", plugins: [Jido.Memory.Plugin]

  memory do
    source(:project, operations: [taxonomy: SupportDesk.PalaceTaxonomy, search: SupportDesk.SearchPalaceRooms])
  end

  routes do
    signal_source("/examples/memory/project")

    route "examples.memory.project.ask", SupportDesk.NavigatePalaceFlow, as: :ask do
      state(:unchanged)
      reply("examples.memory.project.answer", from: output(:trace))
    end
  end
end

alias Jido.Memory.MemPalace
alias SupportDesk.{Inference, ProjectPalaceAgent}

fixture = fn model, prompt, _options ->
  %{content: [%{text: text}]} = List.last(prompt.messages)
  true = String.contains?(text, "[billing/callback.md]")
  Inference.fixture_reply(model, prompt, "Use REFUND_RECEIPT [billing/callback.md].")
end

database =
  Path.join(
    System.tmp_dir!(),
    "jido-memory-project-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  )

File.mkdir!(database)

palace = [
  namespace: "project:support",
  wing: "support",
  backend: :local,
  backend_opts: [database: Path.join(database, "palace.sqlite3")]
]

try do
  {:ok, import} = MemPalace.import_project(Path.join(__DIR__, "fixtures"), palace)
  %{metadata: %{imported_files: 2}} = import

  agent = ProjectPalaceAgent.instantiate!(id: "project-research")

  signal =
    ProjectPalaceAgent.ask_signal!(%{question: "Which callback token acknowledges a refund?", term: "callback token"})

  context = %{palace: palace, inference: Inference.from_args!(System.argv(), fixture)}
  {:ok, _, [%{signal: reply}]} = ProjectPalaceAgent.cmd(agent, signal, context: context)

  %{navigation: navigation, call: call} = reply.data
  ["auth", "billing"] = navigation.broad_hits |> Enum.map(& &1.placement["room"]) |> Enum.uniq() |> Enum.sort()
  %{"wing" => "support", "room" => "billing"} = navigation.filter
  true = Enum.all?(navigation.narrowed_hits, &(&1.placement["room"] == "billing"))
  "billing/callback.md" = navigation.selected.path

  %{content: input} = List.last(call.model_input)
  true = String.contains?(input, "billing/callback.md")
  true = String.contains?(input, "REFUND_RECEIPT")
  false = String.contains?(input, ["auth/callback.md", "LOGIN_CHALLENGE"])

  IO.puts(Jason.encode!(%{imported_files: import.metadata.imported_files, trace: reply.data}, pretty: true))
after
  File.rm_rf!(database)
end
