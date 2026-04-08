defmodule Jido.Memory.Capability.Lifecycle do
  @moduledoc """
  Optional provider capability for lifecycle and consolidation operations.
  """

  alias Jido.Memory.ConsolidationResult

  @callback consolidate(map() | struct(), keyword()) ::
              {:ok, ConsolidationResult.t()} | {:error, term()}
end
