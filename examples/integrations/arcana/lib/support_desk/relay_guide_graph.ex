defmodule SupportDesk.RelayGuideGraph do
  @moduledoc false

  alias SupportDesk.GuideIndex

  def seed!(opts) do
    symptom = "S17 refund charge alert means a stalled settlement relay."

    docs = [
      {"v1.0", "guides/symptoms.md", symptom},
      {"v1.0", "guides/repair.md", "To prime the settlement relay, open Operations > Relay and select Prime."},
      {"v2.0", "guides/symptoms.md", symptom},
      {"v2.0", "guides/repair.md", "To clear the settlement relay, select Replace Node."}
    ]

    for {version, path, text} <- docs do
      guide = %{package: "relay_kit", version: version, path: path, commit: "linked-relay-fixture-" <> version}
      {:ok, %{status: "indexed"}} = GuideIndex.index(guide, text, options(opts))
    end

    :ok
  end

  def options(opts) do
    Keyword.merge(opts,
      graph: true,
      graph_depth: 1,
      entity_matcher: :ner,
      entity_extractor: &entities/2,
      relationship_extractor: &relationships/3
    )
  end

  defp entities(text, _opts) do
    {:ok,
     for name <- ["S17", "settlement relay"], String.contains?(text, name) do
       %{name: name, type: "concept", description: name}
     end}
  end

  defp relationships(_text, ["S17", "settlement relay"], _opts) do
    {:ok, [%{source: "S17", target: "settlement relay", type: "INDICATES", strength: 10}]}
  end

  defp relationships(_text, _entities, _opts), do: {:ok, []}
end
