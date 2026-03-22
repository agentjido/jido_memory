defmodule Jido.Memory.LongTermStore do
  @moduledoc """
  Behavior contract for pluggable long-term memory backends.

  The built-in Tiered provider always routes `:long` tier operations through this
  behavior. The default implementation is ETS-backed, and applications can swap
  in custom long-term persistence backends without changing the Tiered provider
  contract.
  """

  alias Jido.Memory.Query
  alias Jido.Memory.Record

  @type target :: map() | struct()
  @type backend_meta :: map()
  @type backend_opts :: keyword()

  @callback validate_config(backend_opts()) :: :ok | {:error, term()}
  @callback init(backend_opts()) :: {:ok, backend_meta()} | {:error, term()}

  @callback remember(target(), map() | keyword(), keyword()) ::
              {:ok, Record.t()} | {:error, term()}

  @callback get(target(), String.t(), keyword()) :: {:ok, Record.t()} | {:error, term()}

  @callback retrieve(target(), Query.t() | map() | keyword(), keyword()) ::
              {:ok, [Record.t()]} | {:error, term()}

  @callback forget(target(), String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}

  @callback prune(target(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}

  @callback info(backend_meta(), :all | [atom()]) :: {:ok, map()} | {:error, term()}
end
