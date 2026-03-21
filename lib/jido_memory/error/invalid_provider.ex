defmodule Jido.Memory.Error.InvalidProvider do
  @moduledoc """
  Typed provider error reserved for internal dispatch and contract tests.
  """

  defexception [:provider, :reason, :message]

  @impl true
  def exception(opts) do
    provider = Keyword.get(opts, :provider)
    reason = Keyword.get(opts, :reason, :invalid)

    %__MODULE__{
      provider: provider,
      reason: reason,
      message: "invalid memory provider: #{inspect(provider)}"
    }
  end
end
