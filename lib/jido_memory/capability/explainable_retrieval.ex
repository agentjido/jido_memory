defmodule Jido.Memory.Capability.ExplainableRetrieval do
  @moduledoc """
  Optional provider capability for retrieval explanations.
  """

  alias Jido.Memory.{Explanation, Query}

  @callback explain_retrieval(map() | struct(), Query.t() | map() | keyword(), keyword()) ::
              {:ok, Explanation.t()} | {:error, term()}
end
