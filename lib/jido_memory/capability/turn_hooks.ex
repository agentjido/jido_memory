defmodule Jido.Memory.Capability.TurnHooks do
  @moduledoc """
  Optional capability for framework turn hooks.
  """

  @callback pre_turn(map() | struct(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback post_turn(map() | struct(), keyword()) :: {:ok, map()} | {:error, term()}
end
