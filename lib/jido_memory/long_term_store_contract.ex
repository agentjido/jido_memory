defmodule Jido.Memory.LongTermStoreContract do
  @moduledoc """
  Helper functions for verifying `Jido.Memory.LongTermStore` backends.

  This module is intended for first-party and third-party backend contract tests.
  """

  alias Jido.Memory.LongTermStore
  alias Jido.Memory.Record

  @type backend_input :: module() | {module(), keyword()}

  @type core_flow_result :: %{
          meta: map(),
          record: Record.t(),
          upserted: Record.t(),
          fetched: Record.t(),
          records: [Record.t()],
          deleted?: boolean()
        }

  @type prune_flow_result :: %{
          meta: map(),
          expired: Record.t(),
          active: Record.t(),
          pruned: non_neg_integer(),
          deleted?: boolean()
        }

  @doc "Returns the minimum query subset expected from production-ready durable backends."
  @spec production_ready_query_subset() :: [atom()]
  def production_ready_query_subset, do: LongTermStore.production_ready_query_subset()

  @doc "Initializes backend metadata from a module or `{module, opts}` tuple."
  @spec backend_meta(backend_input()) :: {:ok, map()} | {:error, term()}
  def backend_meta(backend) do
    with {:ok, ref} <- backend_ref(backend),
         :ok <- ref.module.validate_config(ref.opts) do
      ref.module.init(ref.opts)
    end
  end

  @doc """
  Exercises the overlapping core durable-backend flow:

  - validate and init
  - remember
  - upsert the same record id
  - fetch by id
  - retrieve by structured query
  - forget by id
  """
  @spec exercise_core_flow(backend_input(), map() | struct(), map(), map() | keyword(), keyword()) ::
          {:ok, core_flow_result()} | {:error, term()}
  def exercise_core_flow(backend, target, attrs, query, runtime_opts \\ [])
      when is_map(attrs) and is_list(runtime_opts) do
    with {:ok, ref} <- backend_ref(backend),
         :ok <- ref.module.validate_config(ref.opts),
         {:ok, meta} <- ref.module.init(ref.opts),
         opts <- Keyword.merge(ref.opts, runtime_opts),
         {:ok, record} <- ref.module.remember(target, attrs, opts),
         {:ok, upserted} <- ref.module.remember(target, upsert_attrs(record), opts),
         {:ok, fetched} <- ref.module.get(target, record.id, opts),
         {:ok, records} <- ref.module.retrieve(target, query, opts),
         {:ok, deleted?} <- ref.module.forget(target, record.id, opts) do
      {:ok,
       %{
         meta: meta,
         record: record,
         upserted: upserted,
         fetched: fetched,
         records: records,
         deleted?: deleted?
       }}
    end
  end

  @doc """
  Exercises prune semantics for expired and active records in one namespace.
  """
  @spec exercise_prune_flow(backend_input(), map() | struct(), map(), map(), keyword()) ::
          {:ok, prune_flow_result()} | {:error, term()}
  def exercise_prune_flow(backend, target, expired_attrs, active_attrs, runtime_opts \\ [])
      when is_map(expired_attrs) and is_map(active_attrs) and is_list(runtime_opts) do
    with {:ok, ref} <- backend_ref(backend),
         :ok <- ref.module.validate_config(ref.opts),
         {:ok, meta} <- ref.module.init(ref.opts),
         opts <- Keyword.merge(ref.opts, runtime_opts),
         {:ok, expired} <- ref.module.remember(target, expired_attrs, opts),
         {:ok, active} <- ref.module.remember(target, active_attrs, opts),
         {:ok, pruned} <- ref.module.prune(target, opts),
         {:ok, deleted?} <- ref.module.forget(target, active.id, opts) do
      {:ok, %{meta: meta, expired: expired, active: active, pruned: pruned, deleted?: deleted?}}
    end
  end

  defp backend_ref({module, opts}) when is_atom(module) and is_list(opts),
    do: {:ok, %{module: module, opts: opts}}

  defp backend_ref(module) when is_atom(module), do: {:ok, %{module: module, opts: []}}
  defp backend_ref(other), do: {:error, {:invalid_long_term_store, other}}

  defp upsert_attrs(%Record{} = record) do
    metadata =
      record.metadata
      |> normalize_map()
      |> Map.put(:contract, %{updated: true})

    record
    |> Map.from_struct()
    |> Map.put(:text, upserted_text(record.text))
    |> Map.put(:metadata, metadata)
  end

  defp upserted_text(text) when is_binary(text) and text != "", do: text <> " updated"
  defp upserted_text(_text), do: "updated"

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_other), do: %{}
end
