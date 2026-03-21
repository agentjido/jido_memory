defmodule Jido.Memory.Provider do
  @moduledoc """
  Canonical provider contract for pluggable memory implementations.

  `retrieve/3` is the canonical read operation. `Jido.Memory.Runtime.recall/2`
  remains available as a compatibility facade over provider retrieval.
  """

  alias Jido.Memory.Query
  alias Jido.Memory.Record

  @type target :: map() | struct()
  @type provider_meta :: map()
  @type provider_opts :: keyword()
  @type retrieve_query :: Query.t() | map() | keyword()
  @type info_fields :: :all | [atom()]

  @callback validate_config(provider_opts()) :: :ok | {:error, term()}
  @callback child_specs(provider_opts()) :: [Supervisor.child_spec()]
  @callback init(provider_opts()) :: {:ok, provider_meta()} | {:error, term()}
  @callback capabilities(provider_meta()) :: map()

  @callback remember(target(), map() | keyword(), keyword()) ::
              {:ok, Record.t()} | {:error, term()}
  @callback get(target(), String.t(), keyword()) :: {:ok, Record.t()} | {:error, term()}
  @callback retrieve(target(), retrieve_query(), keyword()) ::
              {:ok, [Record.t()]} | {:error, term()}
  @callback forget(target(), String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  @callback prune(target(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  @callback info(provider_meta(), info_fields()) :: {:ok, map()} | {:error, term()}
end
