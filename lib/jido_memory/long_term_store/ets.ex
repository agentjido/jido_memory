defmodule Jido.Memory.LongTermStore.ETS do
  @moduledoc """
  Default long-term backend backed by `Jido.Memory.Store` through the Basic provider.
  """

  @behaviour Jido.Memory.LongTermStore

  alias Jido.Memory.Provider.Basic
  alias Jido.Memory.Store

  @default_store {Jido.Memory.Store.ETS, [table: :jido_memory_long]}

  @impl true
  def validate_config(opts) when is_list(opts) do
    store = Keyword.get(opts, :store, @default_store)
    store_opts = Keyword.get(opts, :store_opts, [])

    with {:ok, _normalized} <- Store.normalize_store(store),
         true <- is_list(store_opts) do
      :ok
    else
      false -> {:error, :invalid_store_opts}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_config(_opts), do: {:error, :invalid_long_term_store_opts}

  @impl true
  def init(opts) do
    with :ok <- validate_config(opts),
         {:ok, {store_mod, store_opts}} <- normalize_store(opts),
         :ok <- store_mod.ensure_ready(store_opts) do
      {:ok,
       %{
         backend: __MODULE__,
         store: {store_mod, store_opts}
       }}
    end
  end

  @impl true
  def remember(target, attrs, opts) do
    with {:ok, runtime_opts} <- runtime_opts(opts) do
      Basic.remember(target, attrs, runtime_opts)
    end
  end

  @impl true
  def get(target, id, opts) do
    with {:ok, runtime_opts} <- runtime_opts(opts) do
      Basic.get(target, id, runtime_opts)
    end
  end

  @impl true
  def retrieve(target, query, opts) do
    with {:ok, runtime_opts} <- runtime_opts(opts) do
      Basic.retrieve(target, query, runtime_opts)
    end
  end

  @impl true
  def forget(target, id, opts) do
    with {:ok, runtime_opts} <- runtime_opts(opts) do
      Basic.forget(target, id, runtime_opts)
    end
  end

  @impl true
  def prune(target, opts) do
    with {:ok, runtime_opts} <- runtime_opts(opts) do
      Basic.prune(target, runtime_opts)
    end
  end

  @impl true
  def info(backend_meta, :all), do: {:ok, backend_meta}

  def info(backend_meta, fields) when is_list(fields) do
    {:ok, Map.take(backend_meta, fields)}
  end

  def info(_backend_meta, _fields), do: {:error, :invalid_info_fields}

  defp normalize_store(opts) do
    store = Keyword.get(opts, :store, @default_store)
    store_opts = Keyword.get(opts, :store_opts, [])

    with {:ok, {store_mod, base_opts}} <- Store.normalize_store(store),
         true <- is_list(store_opts) do
      {:ok, {store_mod, Keyword.merge(base_opts, store_opts)}}
    else
      false -> {:error, :invalid_store_opts}
      {:error, reason} -> {:error, reason}
    end
  end

  defp runtime_opts(opts) do
    namespace = Keyword.get(opts, :namespace)

    with true <- is_binary(namespace) and String.trim(namespace) != "",
         {:ok, {store_mod, store_opts}} <- normalize_store(opts) do
      {:ok, [namespace: namespace, store: {store_mod, store_opts}]}
    else
      false -> {:error, :namespace_required}
      {:error, _reason} = error -> error
    end
  end
end
