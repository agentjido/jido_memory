defmodule Jido.Memory.Actions.Access do
  @moduledoc """
  Runs a named Action from an Agent's memory DSL in a Flow step.

      step "search",
        action: Jido.Memory.Actions.Access,
        params: %{
          kind: :index,
          name: :guides,
          operation: :search,
          input: %{version: input(:version), question: input(:question)}
        }

  The bound Action receives the `:input` and the current Turn context.
  Use a native Flow step or `invoke` for a child Flow. Use a root `handoff`
  to select a Flow with waits on a durable host.
  Pass the complete step result to downstream code. Use an inline step
  with a declared output schema when downstream steps reference its fields.
  """

  alias Jido.{Joi, Memory}

  use Jido.Action,
    name: "jido_memory_access",
    schema:
      Joi.object(%{
        kind: Joi.enum([:source, :index, :graph]),
        name: Joi.atom(),
        operation: Joi.atom(),
        input: Joi.map() |> Joi.default(%{})
      })

  @impl true
  def run(%{kind: kind, name: name, operation: operation, input: input}, context) do
    case Memory.access(context, kind, name, operation, input) do
      {:handoff, _successor, _effects} -> {:error, :memory_operation_requires_handoff}
      result -> result
    end
  end
end
