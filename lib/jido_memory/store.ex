defmodule Jido.Memory.Store do
  @moduledoc """
  Storage adapter behavior for memory persistence and retrieval.

  `jido_memory` ships with ETS and Redis implementations, but callers only
  depend on this behavior so they can migrate to other storage backends later
  without API churn.
  """

  alias Jido.Memory.Query
  alias Jido.Memory.Record

  @required_callbacks [ensure_ready: 1, put: 2, get: 2, delete: 2, query: 2, prune_expired: 1]

  @type opts :: keyword()
  @type key :: {namespace :: String.t(), id :: String.t()}
  @type store :: module() | {module(), keyword()}

  @callback ensure_ready(opts()) :: :ok | {:error, term()}
  @callback validate_options(opts()) :: :ok | {:error, term()}
  @callback put(Record.t(), opts()) :: {:ok, Record.t()} | {:error, term()}
  @callback get(key(), opts()) :: {:ok, Record.t()} | :not_found | {:error, term()}
  @callback delete(key(), opts()) :: :ok | {:error, term()}
  @callback query(Query.t(), opts()) :: {:ok, [Record.t()]} | {:error, term()}
  @callback prune_expired(opts()) :: {:ok, non_neg_integer()} | {:error, term()}

  @optional_callbacks validate_options: 1

  @doc "Normalizes store declarations into `{module, opts}` tuples."
  @spec normalize_store(store() | nil) :: {:ok, {module(), keyword()}} | {:error, term()}
  def normalize_store(nil), do: {:error, :missing_store}
  def normalize_store({mod, opts}) when is_atom(mod) and is_list(opts), do: {:ok, {mod, opts}}
  def normalize_store(mod) when is_atom(mod), do: {:ok, {mod, []}}
  def normalize_store(other), do: {:error, {:invalid_store, other}}

  @doc "Validates store-specific options when the store exports `validate_options/1`."
  @spec validate_options(module(), opts()) :: :ok | {:error, term()}
  def validate_options(store_mod, opts) when is_atom(store_mod) and is_list(opts) do
    with {:ok, loaded} <- ensure_loaded(store_mod),
         :ok <- ensure_callbacks(loaded) do
      if function_exported?(loaded, :validate_options, 1) do
        loaded.validate_options(opts)
      else
        :ok
      end
    end
  end

  @doc "Fetches a single record and normalizes not-found semantics."
  @spec fetch(module(), key(), opts()) :: {:ok, Record.t()} | {:error, term()}
  def fetch(store_mod, key, opts) when is_atom(store_mod) and is_list(opts) do
    case store_mod.get(key, opts) do
      {:ok, record} -> {:ok, record}
      :not_found -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp ensure_loaded(module) do
    case Code.ensure_loaded(module) do
      {:module, loaded} -> {:ok, loaded}
      {:error, reason} -> {:error, {:store_not_loaded, module, reason}}
    end
  end

  defp ensure_callbacks(module) do
    missing =
      Enum.reject(@required_callbacks, fn {name, arity} ->
        function_exported?(module, name, arity)
      end)

    if missing == [] do
      :ok
    else
      {:error, {:invalid_store, {module, missing}}}
    end
  end
end
