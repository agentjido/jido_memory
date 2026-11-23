defmodule Jido.Memory.Plugin do
  @moduledoc "Defines memory collections, read grants, and named operations for an Agent."

  @missing_memory "Declare at least one memory collection, source, index, or graph"

  use Jido.Plugin,
    id: "jido.memory",
    sections: [Jido.Memory.DSL.section()],
    imports: [Jido.Memory.DSL],
    option_keys: [agent: [:collections, :flow, :reads, :bindings], agent_server: [:collections]]

  alias Jido.{Agent, Error, Joi}
  alias Jido.Agent.Plugin.Reduction
  alias Jido.Memory.Directive.{Forget, Remember}
  alias Jido.Memory.Entry
  alias Jido.Memory.ReasoningVerifier

  defoverridable verifiers: 0

  @impl Spark.Dsl.Extension
  @doc false
  def verifiers, do: super() ++ [ReasoningVerifier]

  @impl Jido.Agent.Extension
  defdelegate lower(dsl, config), to: Jido.Memory.DSL

  @impl Jido.Agent.Extension
  def normalize(%{collections: collections} = config) when is_map(collections) and not is_struct(collections) do
    {bindings, collection_config} = Map.pop(config, :bindings, %{})

    with :ok <- validate_bindings(bindings),
         :ok <- require_memory(collections, bindings),
         :ok <- validate_entries(collections, &validate_collection/2),
         :ok <- validate_binding(collection_config) do
      {:ok, config}
    end
  end

  def normalize(_config), do: invalid_config(@missing_memory)

  defp require_memory(collections, bindings) when map_size(collections) > 0 or map_size(bindings) > 0, do: :ok
  defp require_memory(_, _), do: invalid_config(@missing_memory)

  @impl Jido.Plugin
  def state_spec(opts) do
    fields =
      for {name, %{schema: value_schema, max_entries: max_entries}} <- opts[:collections],
          into: %{} do
        record = Joi.object(%{key: Joi.string(), value: value_schema, source_signal_id: Joi.string()})
        {name, record |> Joi.list() |> Joi.max(max_entries) |> Joi.default([])}
      end

    {:memory, Joi.object(fields) |> Joi.default(%{})}
  end

  @impl Jido.Plugin
  def prepare(preparation, opts) do
    reads =
      case preparation.route_candidates do
        [%{handler: %{kind: :flow, target: flow}}] ->
          if flow == opts[:flow], do: opts[:reads] || %{}, else: %{}

        _ ->
          %{}
      end

    {:ok, %{collections: opts[:collections], reads: reads, bindings: opts[:bindings] || %{}}}
  end

  @impl Jido.Plugin
  def admit(_runtime, _admission, opts) do
    external? = Enum.any?(opts[:collections], fn {_name, collection} -> not state_collection?(collection) end)
    {:ok, if(external?, do: :live)}
  end

  @impl Jido.Plugin
  def directives(_opts), do: [Remember, Forget]

  @impl Jido.Plugin
  def reduce(%Reduction{} = reduction, opts) do
    collections = opts[:collections]

    Enum.reduce_while(reduction.directives, {:ok, reduction.plugin_state}, fn directive, {:ok, memory} ->
      case apply_directive(directive, memory, collections, reduction.signal.id) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @doc false
  def fetch_collection(collections, name) do
    case Map.fetch(collections, name) do
      {:ok, collection} -> {:ok, collection}
      :error -> {:error, {:unknown_collection, name}}
    end
  end

  defp validate_bindings(bindings) when is_map(bindings) and not is_struct(bindings) do
    validate_entries(bindings, fn
      kind, named
      when kind in [:source, :index, :graph] and is_map(named) and not is_struct(named) and map_size(named) > 0 ->
        validate_entries(named, &validate_operations/2)

      _, _ ->
        invalid_config("Invalid memory binding")
    end)
  end

  defp validate_bindings(_), do: invalid_config("Invalid memory bindings")

  defp validate_operations(name, operations)
       when is_atom(name) and name not in [nil, true, false, :__struct__] and
              is_map(operations) and not is_struct(operations) and map_size(operations) > 0 do
    validate_entries(operations, fn
      operation, target
      when is_atom(operation) and operation not in [nil, true, false, :__struct__] and is_atom(target) ->
        with {:module, ^target} <- Code.ensure_compiled(target),
             {:ok, _instruction} <- Jido.Instruction.resolve(target) do
          :ok
        else
          _ -> invalid_config("Memory operation #{inspect(name)}.#{operation} requires a Jido Action or Flow")
        end

      _, _ ->
        invalid_config("Invalid operation in memory binding #{inspect(name)}")
    end)
  end

  defp validate_operations(name, _operations),
    do: invalid_config("Memory binding #{inspect(name)} requires at least one operation")

  defp validate_binding(config) when map_size(config) == 1, do: :ok

  defp validate_binding(%{flow: flow, reads: reads, collections: collections} = config)
       when map_size(config) == 3 and is_atom(flow) and not is_struct(reads) and map_size(reads) > 0 do
    with {:module, ^flow} <- Code.ensure_compiled(flow),
         {:ok, %{kind: :flow}} <- Jido.Instruction.resolve(flow) do
      validate_entries(reads, fn name, read -> validate_read(name, read, collections) end)
    else
      _ -> invalid_config("Memory read grants require a Jido Flow")
    end
  end

  defp validate_binding(_config), do: invalid_config("Declare a Flow with at least one memory read grant")

  defp validate_read(
         name,
         %{collection: collection, filters: filters, expose: expose, limit: limit} = read,
         collections
       )
       when is_atom(name) and not is_struct(read) and map_size(read) == 4 and
              is_list(filters) and is_list(expose) and expose != [] and limit in 1..100 do
    with {:ok, %{schema: schema} = definition} <- fetch_collection(collections, collection),
         {:ok, fields} <- Joi.Schema.fields(schema),
         true <- Enum.all?(filters ++ expose, &Keyword.has_key?(fields, &1)),
         :ok <- Jido.Memory.Store.validate_filter_fields(definition, filters) do
      :ok
    else
      _ -> invalid_config("Memory read #{inspect(name)} must name a collection and its supported fields")
    end
  end

  defp validate_read(name, _read, _collections), do: invalid_config("Invalid memory read grant #{inspect(name)}")

  defp validate_entries(entries, validate) do
    Enum.reduce_while(entries, :ok, fn {name, entry}, :ok ->
      case validate.(name, entry) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_collection(name, %{schema: schema} = collection)
       when is_atom(name) and name not in [nil, true, false, :__struct__] do
    with :map <- Joi.Schema.kind(schema),
         {:ok, fields} when is_list(fields) <- Joi.Schema.fields(schema),
         :ok <- Joi.validate_stored_schema(schema) do
      validate_store(name, collection, fields)
    else
      _ -> invalid_config("Memory collection #{inspect(name)} requires a stored Joi object schema")
    end
  end

  defp validate_collection(name, _collection), do: invalid_config("Invalid memory collection #{inspect(name)}")

  defp validate_store(_name, %{max_entries: limit} = collection, _fields)
       when is_integer(limit) and limit > 0 and
              (map_size(collection) == 2 or
                 (map_size(collection) == 3 and :erlang.map_get(:store, collection) == :agent_state)),
       do: :ok

  defp validate_store(name, %{store: {adapter, config}} = collection, fields)
       when map_size(collection) == 2 and is_atom(adapter) and is_map(config) and not is_struct(config) do
    with {:module, ^adapter} <- Code.ensure_compiled(adapter),
         true <- function_exported?(adapter, :recall, 5) and function_exported?(adapter, :validate_config, 1),
         :ok <- adapter.validate_config(config),
         :ok <- Jido.Memory.Store.validate_schema_fields(collection, Keyword.keys(fields)) do
      :ok
    else
      _ -> invalid_config("Invalid store binding for memory collection #{inspect(name)}")
    end
  end

  defp validate_store(name, _collection, _fields),
    do:
      invalid_config("Use max_entries for Agent state or declare a read-only external_collection for #{inspect(name)}")

  defp state_collection?(collection), do: Map.get(collection, :store, :agent_state) == :agent_state

  defp require_state_collection(collection) do
    if state_collection?(collection), do: :ok, else: {:error, :external_memory_write_requires_host}
  end

  defp invalid_config(message), do: {:error, Error.validation_error(message, path: [:memory])}

  defp apply_directive(%Remember{} = directive, memory, collections, source_id) do
    with {:ok, collection} <- fetch_collection(collections, directive.collection),
         :ok <- require_state_collection(collection),
         :ok <- Entry.validate_key(directive.key),
         :ok <- Agent.Schema.static(directive.value),
         :ok <- Joi.validate(collection.schema, directive.value) do
      record = %{key: directive.key, value: directive.value, source_signal_id: source_id}

      updated =
        Map.update!(memory, directive.collection, fn records ->
          [record | remove_key(records, directive.key)] |> Enum.take(collection.max_entries)
        end)

      {:ok, updated}
    end
  end

  defp apply_directive(%Forget{} = directive, memory, collections, _source_id) do
    with {:ok, collection} <- fetch_collection(collections, directive.collection),
         :ok <- require_state_collection(collection),
         :ok <- Entry.validate_key(directive.key) do
      {:ok, Map.update!(memory, directive.collection, &remove_key(&1, directive.key))}
    end
  end

  defp apply_directive(_directive, memory, _collections, _source_id), do: {:ok, memory}

  defp remove_key(records, key), do: Enum.reject(records, &(&1.key == key))
end
