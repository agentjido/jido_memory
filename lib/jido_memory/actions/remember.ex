defmodule Jido.Memory.Actions.Remember do
  @moduledoc """
  Explicit action for writing one memory record.
  """

  use Jido.Action,
    name: "memory_remember",
    description: "Write a memory record",
    schema: [
      id: [type: :string, required: false, doc: "Optional record id"],
      namespace: [type: :string, required: false, doc: "Override namespace"],
      class: [type: :any, required: false, doc: "Memory class"],
      kind: [type: :any, required: false, doc: "Memory kind"],
      text: [type: :any, required: false, doc: "Searchable text"],
      content: [type: :any, required: false, doc: "Structured payload"],
      tags: [type: :any, required: false, doc: "Tag list"],
      source: [type: :any, required: false, doc: "Source string"],
      observed_at: [type: :any, required: false, doc: "Timestamp ms"],
      expires_at: [type: :any, required: false, doc: "Expiration timestamp ms"],
      embedding: [type: :any, required: false, doc: "Optional embedding payload"],
      metadata: [type: :any, required: false, doc: "Metadata map"],
      tier: [type: :any, required: false, doc: "Tiered provider tier override"],
      store: [type: :any, required: false, doc: "Store declaration"],
      store_opts: [type: :any, required: false, doc: "Store options"],
      memory_result_key: [type: :any, required: false, doc: "Optional key for record id result"]
    ]

  @impl true
  def run(params, context) do
    case Jido.Memory.Runtime.remember(context, params, []) do
      {:ok, record} ->
        key = params[:memory_result_key] || :last_memory_id
        {:ok, %{key => record.id}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
