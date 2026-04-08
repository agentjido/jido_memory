defmodule Jido.Memory.Actions.Retrieve do
  @moduledoc """
  Canonical action for querying memory through provider-aware retrieval.
  """

  use Jido.Action,
    name: "memory_retrieve",
    description: "Query memory records and return a canonical retrieval result",
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
      extensions: [type: :any, required: false, doc: "Provider-specific query hints"],
      store: [type: :any, required: false, doc: "Store declaration"],
      store_opts: [type: :any, required: false, doc: "Store options"],
      provider: [type: :any, required: false, doc: "Provider module or alias"],
      provider_opts: [type: :any, required: false, doc: "Provider options"],
      memory_result_key: [type: :any, required: false, doc: "Output map key"]
    ]

  @impl true
  def run(params, context) do
    case Jido.Memory.Runtime.retrieve(context, params) do
      {:ok, result} ->
        key = params[:memory_result_key] || :memory_result
        {:ok, %{key => result}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
