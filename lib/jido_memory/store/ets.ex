defmodule Jido.Memory.Store.ETS do
  @moduledoc """
  A local shared memory store with an explicit owner process.

  Start the owner under the application's supervisor. Records are scoped by
  the configured scope and collection. The owner serializes writes and owns
  the ETS table. Stopping it removes the records.

  A read timeout returns `{:error, :store_timeout}`. A write timeout returns
  `{:error, :write_outcome_unknown}` because the owner can still apply the request.
  """

  use GenServer

  @behaviour Jido.Memory.Store
  alias Jido.Memory.Entry

  @doc "Starts a table owner registered under the required local `:name`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @doc "Upserts a record in a scope. The application supplies the confirmed record."
  @spec put(atom(), String.t(), atom(), term()) :: :ok | {:error, term()}
  def put(server, scope, collection, record) when is_binary(scope) and is_atom(collection) do
    with :ok <- Entry.validate(record) do
      call(server, {:put, {scope, collection, record.key}, record}, :write_outcome_unknown)
    end
  end

  @doc "Deletes a record by its scoped key."
  @spec delete(atom(), String.t(), atom(), String.t()) :: :ok | {:error, term()}
  def delete(server, scope, collection, key) do
    call(server, {:delete, {scope, collection, key}}, :write_outcome_unknown)
  end

  @impl Jido.Memory.Store
  def validate_config(%{name: name, scope: scope} = config)
      when is_atom(name) and name not in [nil, true, false] and is_binary(scope) and byte_size(scope) > 0 and
             map_size(config) == 2,
      do: :ok

  def validate_config(_config), do: {:error, :invalid_ets_binding}

  @impl Jido.Memory.Store
  def recall(%{name: server, scope: scope}, collection, filters, limit, _context) do
    call(server, {:recall, scope, collection, filters, limit}, :store_timeout)
  end

  @impl GenServer
  def init(:ok), do: {:ok, :ets.new(__MODULE__, [:private, :set])}

  @impl GenServer
  def handle_call({:put, identity, record}, _from, table) do
    :ets.insert(table, {identity, System.unique_integer([:monotonic]), record})
    {:reply, :ok, table}
  end

  def handle_call({:delete, identity}, _from, table) do
    :ets.delete(table, identity)
    {:reply, :ok, table}
  end

  def handle_call({:recall, scope, collection, filters, limit}, _from, table) do
    match = [{{{scope, :"$1", :_}, :_, :_}, [{:"=:=", :"$1", {:const, collection}}], [:"$_"]}]

    records =
      table
      |> :ets.select(match)
      |> Enum.filter(fn {_identity, _order, record} ->
        Enum.all?(filters, fn {field, value} -> Map.fetch(record.value, field) === {:ok, value} end)
      end)
      |> Enum.sort_by(fn {_identity, order, _record} -> order end, :desc)
      |> Enum.take(limit)
      |> Enum.map(fn {_identity, _order, record} -> record end)

    {:reply, {:ok, records}, table}
  end

  defp call(server, request, timeout_reason) do
    GenServer.call(server, request)
  catch
    :exit, {reason, _call} when reason in [:noproc, :normal, :shutdown] -> {:error, :store_unavailable}
    :exit, {:timeout, _call} -> {:error, timeout_reason}
  end
end
