defmodule Jido.Memory.Actions.RecallGranted do
  @moduledoc """
  Retrieves records through a read grant on the Agent's reasoning Flow.

  Returns the decision and the granted fields in their original types. A Flow
  can select, budget, or format the records before it builds a model context.
  """

  alias Jido.{Joi, Memory}
  alias Jido.Memory.Plugin

  use Jido.Action,
    name: "jido_memory_recall_granted",
    schema:
      Joi.object(%{
        grant: Joi.atom(),
        where: Joi.map() |> Joi.default(%{}),
        enabled: Joi.boolean() |> Joi.default(true)
      }),
    output_schema: Joi.object(%{recall: Joi.map()})

  @impl true
  def run(%{enabled: false, grant: grant}, _context), do: decision(grant, :disabled)

  def run(%{grant: grant, where: where}, context) do
    case read_grant(context, grant) do
      nil ->
        decision(grant, :grant_unavailable)

      read ->
        if Enum.all?(Map.keys(where), &(&1 in read.filters)) do
          recall(grant, read, where, context)
        else
          decision(grant, :filter_denied)
        end
    end
  end

  defp read_grant(%{plugin_inputs: %{Plugin => %{prepared: %{reads: reads}}}}, grant), do: Map.get(reads, grant)
  defp read_grant(_context, _grant), do: nil

  defp recall(grant, read, where, context) do
    case Memory.recall(context, read.collection, where: where, limit: read.limit) do
      {:ok, records} ->
        projected = Enum.map(records, &%{&1 | value: Map.take(&1.value, read.expose)})
        decision(grant, :allowed, projected)

      {:error, reason} when reason in [:store_unavailable, :store_timeout, :live_memory_required, :forbidden] ->
        decision(grant, reason)

      {:error, _} = error ->
        error
    end
  end

  defp decision(grant, status, records \\ []), do: {:ok, %{recall: %{grant: grant, decision: status, records: records}}}
end
