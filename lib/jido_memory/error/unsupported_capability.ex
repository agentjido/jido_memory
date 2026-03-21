defmodule Jido.Memory.Error.UnsupportedCapability do
  @moduledoc """
  Typed provider error reserved for internal dispatch and contract tests.
  """

  defexception [:provider, :capability, :message]

  @impl true
  def exception(opts) do
    provider = Keyword.get(opts, :provider)
    capability = Keyword.get(opts, :capability)

    %__MODULE__{
      provider: provider,
      capability: capability,
      message:
        "memory provider #{inspect(provider)} does not support capability #{inspect(capability)}"
    }
  end
end
