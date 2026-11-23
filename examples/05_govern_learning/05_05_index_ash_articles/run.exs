Code.require_file("../../support/inference.exs", __DIR__)

defmodule SupportDesk.SearchArticlesFlow do
  @moduledoc false

  alias Jido.{Joi, Memory}
  alias ReqLLM.Context
  alias SupportDesk.Inference

  use Jido.Flow,
    name: "verify_indexed_articles",
    schema: Joi.object(%{key: Joi.string()}),
    output_schema: Joi.object(%{trace: Joi.map()})

  flow do
    step "retrieve", [key <- input(:key), context <- context()] do
      query = %{
        package: "ash-" <> context.ash.tenant,
        version: "current",
        question: "refund deadline",
        path: "guides/" <> key <> ".md"
      }

      with {:ok, %{evidence: hits}} <- Memory.access(context, :index, :articles, :search, query) do
        {:ok, %{candidate: List.first(hits)}}
      end
    end

    step "reopen", [hit <- result("retrieve", :candidate), context <- context()] do
      {:ok, %{decision: review(hit, context)}}
    end

    step "answer", [check <- result("reopen", :decision), inference <- context(:inference)] do
      line =
        case check do
          %{decision: :accepted, key: key, revision: revision, body: body} -> "[#{key} rev #{revision}] #{body}"
          _ -> "No approved knowledge article."
        end

      {reply, call} =
        Inference.call!(inference, [
          Context.system("Copy the approved evidence line exactly."),
          Context.user("Approved knowledge:\n#{line}")
        ])

      {:ok, %{trace: %{source_check: check, call: call, answer: line, model_text: reply}}}
    end

    output(result("answer"))
  end

  defp review(nil, _context), do: %{decision: :no_candidate}

  defp review(hit, context) do
    key = Map.fetch!(hit.citation, "source_key")
    revision = Map.fetch!(hit.citation, "source_revision")
    base = %{key: key, indexed_revision: revision, document_id: hit.document_id}

    case Memory.access(context, :source, :articles, :read, %{key: key}) do
      {:ok, %{result: %{status: "published", revision: ^revision, body: body}}} ->
        Map.merge(base, %{decision: :accepted, revision: revision, body: body})

      {:ok, %{result: %{status: "withdrawn", revision: actual}}} ->
        Map.merge(base, %{decision: :withdrawn, revision: actual})

      {:ok, %{result: %{revision: actual}}} ->
        Map.merge(base, %{decision: :stale, revision: actual})

      {:error, _reason} ->
        Map.put(base, :decision, :denied)
    end
  end
end

defmodule SupportDesk.ArticlesAgent do
  @moduledoc false

  use Jido.Agent, name: "articles_agent", plugins: [Jido.Memory.Plugin]

  alias Jido.{Joi, Memory}
  alias JidoMemory.Examples.Ash.Articles
  alias SupportDesk.{IndexDocument, IndexStatus, SearchGuides}

  memory do
    source(:articles, operations: [read: Articles.Jido.ReadArticle, list: Articles.Jido.ListArticles])
    index(:articles, operations: [put: IndexDocument, status: IndexStatus, search: SearchGuides])
  end

  routes do
    signal_source("/examples/memory/articles")

    route "examples.memory.articles.import", as: :import_page do
      action %{offset: offset},
        schema: Joi.object(%{offset: Joi.integer(gte: 0)}),
        output_schema: Joi.object(%{trace: Joi.map()}),
        context: context do
        import_page(context, offset)
      end

      state(:unchanged)
      reply("examples.memory.articles.imported", from: output(:trace))
    end

    route "examples.memory.articles.ask", SupportDesk.SearchArticlesFlow, as: :ask do
      state(:unchanged)
      reply("examples.memory.articles.answer", from: output(:trace))
    end
  end

  defp import_page(context, offset) do
    query = %{limit: 1, offset: offset, filter: %{status: "published"}}

    with {:ok, %{page: page, result: articles}} <- Memory.access(context, :source, :articles, :list, query) do
      index_articles(context, articles, page)
    end
  end

  defp index_articles(context, articles, page) do
    Enum.reduce_while(articles, {:ok, []}, fn article, {:ok, indexed} ->
      case index_article(context, article, page) do
        {:ok, entry} -> {:cont, {:ok, [entry | indexed]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, %{trace: %{entries: Enum.reverse(entries)}}}
      {:error, _reason} = error -> error
    end
  end

  defp index_article(context, %{key: key, revision: revision, body: body, status: "published"}, page) do
    guide = %{
      package: "ash-" <> context.ash.tenant,
      version: "current",
      path: "guides/" <> key <> ".md",
      commit: "ash-revision-#{revision}",
      source_key: key,
      source_revision: revision
    }

    with {:ok, %{job_id: id}} <- Memory.access(context, :index, :articles, :put, %{guide: guide, text: body}),
         {:ok, %{job: job}} <- Memory.access(context, :index, :articles, :status, %{job_id: id}) do
      case job do
        %{status: "indexed", document_id: document_id} ->
          {:ok, %{page: page, source_key: key, revision: revision, document_id: document_id}}

        _ ->
          {:error, {:article_index_failed, key}}
      end
    end
  end

  defp index_article(_context, _other, _page), do: {:error, :article_not_published}
end

alias JidoMemory.Examples.Ash.Article
alias SupportDesk.{ArcanaDatabase, ArticlesAgent, Inference}

fixture = fn model, prompt, _options ->
  %{content: [%{text: "Approved knowledge:\n" <> result}]} = List.last(prompt.messages)
  Inference.fixture_reply(model, prompt, result)
end

create = fn tenant, attrs ->
  Ash.create!(Article, Map.merge(%{revision: 1, status: "published", internal_note: "never index this note"}, attrs),
    actor: %{tenant: tenant, role: :admin},
    tenant: tenant
  )
end

article = create.("north", %{key: "HELP-17", body: "The refund deadline is 30 days for North."})
create.("north", %{key: "HELP-18", body: "Confirm the invoice number before any refund."})
create.("north", %{key: "HELP-19", status: "draft", body: "Draft limit is 90 days."})
create.("south", %{key: "HELP-17", body: "The refund deadline is 15 days for South."})

access = %{tenant: "north", actor: %{tenant: "north", may_read: true}}

ArcanaDatabase.with_repo(fn opts ->
  agent = ArticlesAgent.instantiate!(id: "knowledge-support")

  pages =
    Enum.flat_map([0, 1], fn offset ->
      signal = ArticlesAgent.import_page_signal!(%{offset: offset})
      {:ok, _, [%{signal: reply}]} = ArticlesAgent.cmd(agent, signal, context: %{arcana: opts, ash: access})
      reply.data.entries
    end)

  [%{source_key: "HELP-17", page: %{more?: true}}, %{source_key: "HELP-18", page: %{more?: false}}] = pages

  inference = Inference.from_args!(System.argv(), fixture)

  ask = fn key, actor ->
    signal = ArticlesAgent.ask_signal!(%{key: key})

    {:ok, _, [%{signal: reply}]} =
      ArticlesAgent.cmd(agent, signal, context: %{arcana: opts, ash: actor, inference: inference})

    reply.data
  end

  published = ask.("HELP-17", access)
  Ash.update!(article, %{status: "withdrawn", revision: 2}, actor: %{role: :admin, tenant: "north"}, tenant: "north")
  withdrawn = ask.("HELP-17", access)
  denied = ask.("HELP-18", put_in(access.actor.may_read, false))

  %{source_check: %{decision: :accepted, revision: 1, document_id: doc}} = published
  %{source_check: %{decision: :withdrawn, indexed_revision: 1, revision: 2, document_id: ^doc}} = withdrawn
  %{source_check: %{decision: :denied, indexed_revision: 1}} = denied
  %{content: approved_input} = List.last(published.call.model_input)
  true = String.contains?(approved_input, "30 days for North")

  for trace <- [withdrawn, denied] do
    %{content: "Approved knowledge:\nNo approved knowledge article."} = List.last(trace.call.model_input)
  end

  json = Jason.encode!(%{pages: pages, published: published, withdrawn: withdrawn, revoked: denied}, pretty: true)
  false = String.contains?(json, ["never index this note", "15 days for South", "90 days"])
  IO.puts(json)
end)
