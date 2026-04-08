defmodule Jido.Memory.Capability.Ingestion do
  @moduledoc """
  Optional provider capability for batch ingestion flows.
  """

  alias Jido.Memory.{IngestRequest, IngestResult}

  @callback ingest(map() | struct(), IngestRequest.t() | map() | keyword(), keyword()) ::
              {:ok, IngestResult.t()} | {:error, term()}
end
