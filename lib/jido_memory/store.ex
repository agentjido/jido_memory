defmodule Jido.Memory.Store do
  @moduledoc """
  Read contract for an `external_collection`.

  An Agent author binds the adapter and its scope in a collection. Recall
  through this binding requires a live Agent Turn. The adapter returns
  complete records in newest-first order for the requested collection and
  scope. Filter before applying the result limit. The application owns writes
  and retention for the collection.
  """

  @callback validate_config(map()) :: :ok | {:error, term()}
  @callback recall(map(), atom(), map(), pos_integer(), map()) ::
              {:ok, [Jido.Memory.entry()]} | {:error, term()}

  @doc "Lists the supported value filters. Omit this callback to support all declared fields."
  @callback filter_fields(map()) :: [atom()]
  @optional_callbacks filter_fields: 1

  @doc false
  @spec validate_schema_fields(map(), [atom()]) :: :ok | {:error, :unknown_store_filter_field}
  def validate_schema_fields(%{store: {adapter, config}}, fields) do
    case filter_fields(adapter, config) do
      :all -> :ok
      supported -> if supported -- fields == [], do: :ok, else: {:error, :unknown_store_filter_field}
    end
  end

  @doc false
  @spec validate_filter_fields(map(), [atom()]) :: :ok | {:error, {:unsupported_store_filter, atom()}}
  def validate_filter_fields(%{store: {adapter, config}}, fields) do
    case filter_fields(adapter, config) do
      :all ->
        :ok

      supported ->
        case fields -- supported do
          [] -> :ok
          [field | _] -> {:error, {:unsupported_store_filter, field}}
        end
    end
  end

  def validate_filter_fields(_definition, _fields), do: :ok

  defp filter_fields(adapter, config) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :filter_fields, 1),
      do: adapter.filter_fields(config),
      else: :all
  end
end
