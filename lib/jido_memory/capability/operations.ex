defmodule Jido.Memory.Capability.Operations do
  @moduledoc """
  Optional operational capability for provider observability and control.
  """

  @callback metrics(keyword()) :: {:ok, map()} | {:error, term()}
  @callback audit_events(keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback journal_events(keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback cancel_pending(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
end
