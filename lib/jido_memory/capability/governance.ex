defmodule Jido.Memory.Capability.Governance do
  @moduledoc """
  Optional governance capability for policy and approval flows.
  """

  @callback issue_approval_token(keyword()) :: {:ok, map()} | {:error, term()}
  @callback current_policy(keyword()) :: {:ok, map()} | {:error, term()}
end
