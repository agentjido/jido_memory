defmodule Jido.Memory.Store.Ash do
  @moduledoc """
  Connects a memory collection to application-owned AshJido Actions.

  The application supplies four generated Actions and the live Ash actor
  and tenant for each call. The Actions accept the collection name as a
  string and serialize records with `:key`, `:value`, and
  `:source_signal_id` fields. The query Action receives `:collection`,
  `:where` (exact value filters), and `:limit`. It applies collection and
  value filters before the limit. Declare its supported value fields in
  the binding's `:filter_fields`.
  """

  @behaviour Jido.Memory.Store

  @impl true
  def validate_config(%{put: put, get: get, query: query, delete: delete, filter_fields: fields} = binding)
      when map_size(binding) == 5 and is_list(fields) do
    cond do
      List.improper?(fields) or not Enum.all?(fields, &is_atom/1) -> {:error, :invalid_ash_filter_fields}
      not Enum.all?([put, get, query, delete], &generated_action?/1) -> {:error, :invalid_ash_actions}
      true -> :ok
    end
  end

  def validate_config(_binding), do: {:error, :invalid_ash_binding}

  @impl true
  def filter_fields(%{filter_fields: fields}), do: fields

  @doc "Upserts a record through the configured Action in the current Ash scope."
  @spec put(map(), atom(), Jido.Memory.entry(), map()) :: {:ok, Jido.Memory.entry()} | {:error, term()}
  def put(binding, collection, record, context) do
    params = Map.put(record, :collection, Atom.to_string(collection))

    with {:ok, result} <- run(binding.put, params, context) do
      entry(result)
    end
  end

  @doc "Reads one record by scoped key through the configured Action."
  @spec get(map(), atom(), String.t(), map()) :: {:ok, Jido.Memory.entry() | nil} | {:error, term()}
  def get(binding, collection, key, context) do
    case run(binding.get, %{collection: Atom.to_string(collection), key: key}, context) do
      {:ok, nil} -> {:ok, nil}
      {:ok, result} -> entry(result)
      {:error, :not_found} -> {:ok, nil}
      {:error, _} = error -> error
    end
  end

  @impl true
  def recall(binding, collection, filters, limit, context) do
    params = %{collection: Atom.to_string(collection), where: filters, limit: limit}

    with :ok <- Jido.Memory.Store.validate_filter_fields(%{store: {__MODULE__, binding}}, Map.keys(filters)),
         {:ok, results} when is_list(results) <- run(binding.query, params, context) do
      Enum.reduce_while(results, {:ok, []}, fn result, {:ok, entries} ->
        case entry(result) do
          {:ok, record} -> {:cont, {:ok, [record | entries]}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, entries} -> {:ok, Enum.reverse(entries)}
        error -> error
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_ash_memory_result}
    end
  end

  @doc "Deletes a record through the configured Action in the current Ash scope."
  @spec delete(map(), atom(), String.t(), map()) :: :ok | {:error, term()}
  def delete(binding, collection, key, context) do
    case run(binding.delete, %{collection: Atom.to_string(collection), key: key}, context) do
      {:ok, _result} -> :ok
      {:error, :not_found} -> :ok
      {:error, _} = error -> error
    end
  end

  defp run(action, params, %{ash: %{actor: actor, tenant: tenant} = scope})
       when not is_nil(actor) and not is_nil(tenant) do
    case Jido.Exec.run(action, params, %{ash: scope}) do
      {:ok, %{result: result}} -> {:ok, result}
      {:error, %{details: %{reason: reason}}} when reason in [:forbidden, :not_found] -> {:error, reason}
      {:error, _} = error -> error
      _ -> {:error, :invalid_ash_memory_result}
    end
  end

  defp run(_action, _params, _context), do: {:error, :forbidden}

  defp entry(%{key: key, value: value, source_signal_id: source_id} = record)
       when is_binary(key) and is_map(value) and is_binary(source_id),
       do: {:ok, Map.take(record, [:key, :value, :source_signal_id])}

  defp entry(_result), do: {:error, :invalid_ash_memory_result}

  defp generated_action?(action) when is_atom(action) do
    match?({:module, ^action}, Code.ensure_compiled(action)) and function_exported?(action, :__ash_jido__, 0)
  end

  defp generated_action?(_action), do: false
end
