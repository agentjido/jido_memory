defmodule Jido.Memory.Capability.Ingestion do
  @moduledoc """
  Optional capability for provider-defined batch, multimodal, or routed ingestion.
  """

  @callback ingest(map() | struct(), map(), keyword()) :: {:ok, map()} | {:error, term()}
end
