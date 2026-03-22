defmodule Jido.Memory.Actions.Forget do
  @moduledoc """
  Explicit action for deleting one memory record.
  """

  use Jido.Action,
    name: "memory_forget",
    description: "Delete a memory record",
    schema: [
      id: [type: :string, required: true, doc: "Record id"],
      namespace: [type: :string, required: false, doc: "Override namespace"],
      tier: [type: :any, required: false, doc: "Tiered provider tier override"],
      store: [type: :any, required: false, doc: "Store declaration"],
      store_opts: [type: :any, required: false, doc: "Store options"]
    ]

  @impl true
  def run(%{id: id} = params, context) do
    case Jido.Memory.Runtime.forget(context, id, params |> Map.delete(:id) |> Map.to_list()) do
      {:ok, deleted?} -> {:ok, %{last_memory_deleted?: deleted?}}
      {:error, reason} -> {:error, reason}
    end
  end
end
