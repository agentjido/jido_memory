defmodule Jido.Memory.LongTermStore do
  @moduledoc """
  Behavior contract for pluggable long-term memory backends.

  The built-in Tiered provider always routes `:long` tier operations through this
  behavior. The default implementation is ETS-backed, and applications can swap
  in custom long-term persistence backends without changing the Tiered provider
  contract.

  Long-term backends are expected to preserve the canonical `Jido.Memory.Record`
  shape exactly, including provider-managed metadata such as Tiered lifecycle and
  promotion fields.

  Durable backends should also preserve these semantics:

  - `remember/3` is idempotent at the `{namespace, id}` boundary and should
    behave as an upsert when the caller provides an existing record id.
  - `get/3` returns `{:error, :not_found}` when a namespaced record is missing.
  - `forget/3` returns `{:ok, false}` for missing records rather than treating
    absence as an error.
  - `prune/2` removes expired records for the active namespace and returns the
    number pruned.
  - `retrieve/3` must support namespace-scoped structured retrieval. A durable
    backend is considered production-ready when it supports at least the
    overlapping `Jido.Memory.Query` subset returned by
    `production_ready_query_subset/0`.
  """

  alias Jido.Memory.Query
  alias Jido.Memory.Record

  @production_ready_query_subset [
    :classes,
    :kinds,
    :tags_any,
    :tags_all,
    :text_contains,
    :since,
    :until,
    :limit,
    :order
  ]

  @type target :: map() | struct()
  @type backend_meta :: map()
  @type backend_opts :: keyword()

  @doc """
  Returns the minimum structured query fields a durable backend should support.
  """
  @spec production_ready_query_subset() :: [atom()]
  def production_ready_query_subset, do: @production_ready_query_subset

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
