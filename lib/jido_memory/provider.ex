defmodule Jido.Memory.Provider do
  @moduledoc """
  Provider behavior for memory implementations used by `Jido.Memory.Runtime`.
  """

  alias Jido.Memory.{CapabilitySet, ProviderInfo, Query, Record, RetrieveResult}

  @type target :: map() | struct()
  @type provider_opts :: keyword()

  @callback validate_config(provider_opts()) :: :ok | {:error, term()}
  @callback capabilities(provider_opts()) :: {:ok, CapabilitySet.t()} | {:error, term()}
  @callback remember(target(), map() | keyword(), keyword()) ::
              {:ok, Record.t()} | {:error, term()}
  @callback get(target(), String.t(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  @callback retrieve(target(), Query.t() | map() | keyword(), keyword()) ::
              {:ok, RetrieveResult.t()} | {:error, term()}
  @callback forget(target(), String.t(), keyword()) ::
              {:ok, boolean()} | {:error, term()}
  @callback prune(target(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback info(provider_opts(), :all | [atom()]) :: {:ok, ProviderInfo.t()} | {:error, term()}
  @callback child_specs(provider_opts()) :: [Supervisor.child_spec()]

  @optional_callbacks child_specs: 1
end
