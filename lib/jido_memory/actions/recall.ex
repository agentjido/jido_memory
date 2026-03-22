defmodule Jido.Memory.Actions.Recall do
  @moduledoc """
  Compatibility action for querying memory records.
  """

  use Jido.Action,
    name: "memory_recall",
    description: "Query memory records",
    schema: [
      namespace: [type: :string, required: false, doc: "Override namespace"],
      classes: [type: :any, required: false, doc: "Class filters"],
      kinds: [type: :any, required: false, doc: "Kind filters"],
      tags_any: [type: :any, required: false, doc: "Any-tag filter"],
      tags_all: [type: :any, required: false, doc: "All-tag filter"],
      text_contains: [type: :any, required: false, doc: "Case-insensitive text substring"],
      since: [type: :any, required: false, doc: "Start timestamp ms"],
      until: [type: :any, required: false, doc: "End timestamp ms"],
      limit: [type: :any, required: false, doc: "Max result count"],
      order: [type: :any, required: false, doc: "Sort order asc|desc"],
      tier: [type: :any, required: false, doc: "Tiered provider tier override"],
      tiers: [type: :any, required: false, doc: "Tiered provider tier list"],
      tier_mode: [type: :any, required: false, doc: "Tiered provider retrieval mode"],
      query_extensions: [type: :any, required: false, doc: "Provider-native query extensions"],
      store: [type: :any, required: false, doc: "Store declaration"],
      store_opts: [type: :any, required: false, doc: "Store options"],
      memory_result_key: [type: :any, required: false, doc: "Output map key"]
    ]

  @impl true
  def run(params, context) do
    Jido.Memory.Actions.Retrieve.run(params, context)
  end
end
