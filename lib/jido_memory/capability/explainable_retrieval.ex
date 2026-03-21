defmodule Jido.Memory.Capability.ExplainableRetrieval do
  @moduledoc """
  Optional capability for retrieval explanation details.
  """

  @callback explain_retrieval(map() | struct(), term(), keyword()) ::
              {:ok, map()} | {:error, term()}
end
