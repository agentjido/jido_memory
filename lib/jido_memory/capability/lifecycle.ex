defmodule Jido.Memory.Capability.Lifecycle do
  @moduledoc """
  Optional lifecycle capability for provider-level memory maintenance.
  """

  @callback consolidate(map() | struct(), keyword()) :: {:ok, map()} | {:error, term()}
end
