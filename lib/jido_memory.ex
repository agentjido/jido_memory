defmodule Jido.Memory do
  @moduledoc """
  Typed, bounded memory in a Jido v3 Agent.

  Add `Jido.Memory.Plugin` to the Agent's `plugins` and declare a collection:

      memory do
        collection :notes, max_entries: 16 do
          schema Jido.Joi.object(%{text: Jido.Joi.string()})
        end
      end

  Return memory Directives from an Action or Flow to change memory with the
  Turn. Recall reads the state of an Agent or the state at the start of an
  Action's Turn. Each Agent instance owns its state-backed records.

  Use `external_collection` with a store binding for live, read-only access.
  The application owns writes and retention for external records.
  """

  alias Jido.{Agent, Joi}
  alias Jido.Memory.Directive.{Forget, Remember}
  alias Jido.Memory.Entry
  alias Jido.Memory.Plugin
  alias Jido.Memory.Store

  @default_limit 20
  @max_limit 100

  @type entry :: %{key: String.t(), value: map(), source_signal_id: String.t()}

  @doc "Builds a Directive that inserts or replaces a state-backed record by key."
  @spec remember(atom(), String.t(), map()) :: Remember.t()
  def remember(collection, key, value), do: %Remember{collection: collection, key: key, value: value}

  @doc "Builds a Directive that removes a state-backed record by key."
  @spec forget(atom(), String.t()) :: Forget.t()
  def forget(collection, key), do: %Forget{collection: collection, key: key}

  @doc "Recalls records newest first. `:where` matches exact field values. `:limit` defaults to 20 and accepts 1–100."
  @spec recall(Agent.instance() | map(), atom(), keyword()) :: {:ok, [entry()]} | {:error, term()}
  def recall(source, collection, opts \\ []) do
    with {:ok, collections, memory, runtime} <- memory_view(source),
         {:ok, %{schema: schema} = definition} <- Plugin.fetch_collection(collections, collection),
         {:ok, opts} <- Agent.Schema.options(opts, [:where, :limit]),
         limit = Map.get(opts, :limit, @default_limit),
         :ok <- validate_limit(limit),
         where = Map.get(opts, :where, %{}),
         :ok <- validate_filters(schema, where),
         :ok <- Store.validate_filter_fields(definition, Map.keys(where)) do
      read_records(definition, memory, runtime, collection, where, limit, source)
    end
  end

  @doc """
  Runs an Action declared on an Agent's memory source, index, or graph.

  Pass the current Turn context. The target comes from the Agent declaration
  and validates its own inputs. The target uses the Turn's runtime context for
  access checks and connections. Use `operation/4` to resolve a Flow for a
  native invocation or handoff.
  """
  @spec access(map(), :source | :index | :graph, atom(), atom(), map()) :: Jido.Exec.exec_result()
  def access(context, kind, name, operation, params) do
    with {:ok, target} <- operation(context, kind, name, operation),
         {:ok, instruction} <- Jido.Instruction.resolve(target, params, context) do
      case instruction.kind do
        :action -> Jido.Exec.run(instruction)
        :flow -> {:error, :memory_operation_requires_flow_dispatch}
      end
    end
  end

  @doc """
  Resolves a named Action or Flow from the current Turn's memory bindings.

  In a Flow expander, return `{:continue, input, target}` to invoke the resolved
  target. A Flow with waits must run as a root Flow. Select it in a root
  `handoff` with `{:handoff, input, target}` and run it on a durable host.
  """
  @spec operation(map(), :source | :index | :graph, atom(), atom()) :: {:ok, module()} | {:error, term()}
  def operation(context, kind, name, operation) do
    with %{plugin_inputs: %{Plugin => %{prepared: %{bindings: bindings}}}} <- context,
         target when is_atom(target) and not is_nil(target) <- get_in(bindings, [kind, name, operation]) do
      {:ok, target}
    else
      _ -> {:error, {:memory_operation_unavailable, kind, name, operation}}
    end
  end

  defp memory_view(%Agent{plugins: plugins, state: %{memory: memory}}) do
    case Enum.find(plugins, &(&1.provider == Plugin)) do
      %{data: %{collections: collections}} -> {:ok, collections, memory, nil}
      nil -> {:error, :memory_unavailable}
    end
  end

  defp memory_view(%{
         agent_state: %{memory: memory},
         plugin_inputs: %{Plugin => %{prepared: %{collections: collections}} = input}
       }) do
    {:ok, collections, memory, Map.get(input, :runtime)}
  end

  defp memory_view(_source), do: {:error, :memory_unavailable}

  defp read_records(definition, memory, runtime, collection, where, limit, context) do
    case Map.get(definition, :store, :agent_state) do
      :agent_state ->
        records = memory |> Map.fetch!(collection) |> Stream.filter(&matches?(&1.value, where))
        {:ok, Enum.take(records, limit)}

      {adapter, config} when runtime == :live ->
        with {:ok, records} <- adapter.recall(config, collection, where, limit, context) do
          if valid_records?(records, definition.schema, where, limit),
            do: {:ok, Enum.map(records, &Map.take(&1, [:key, :value, :source_signal_id]))},
            else: {:error, :invalid_store_records}
        end

      _ ->
        {:error, :live_memory_required}
    end
  end

  defp valid_records?(records, schema, where, limit) when is_list(records) do
    not List.improper?(records) and length(records) <= limit and
      Enum.all?(records, fn record ->
        Entry.validate(record) == :ok and Joi.validate(schema, record.value) == :ok and matches?(record.value, where)
      end)
  end

  defp valid_records?(_records, _schema, _where, _limit), do: false

  defp validate_limit(limit) when is_integer(limit) and limit in 1..@max_limit, do: :ok
  defp validate_limit(_limit), do: {:error, :invalid_limit}

  defp validate_filters(schema, where) when is_map(where) and not is_struct(where) do
    {:ok, fields} = Joi.Schema.fields(schema)

    Enum.reduce_while(where, :ok, fn {field, value}, :ok ->
      with true <- is_atom(field) and scalar?(value),
           {:ok, field_schema} <- Keyword.fetch(fields, field),
           :ok <- Joi.validate(field_schema, value) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, {:invalid_filter, field}}}
      end
    end)
  end

  defp validate_filters(_schema, _where), do: {:error, :invalid_filters}

  defp scalar?(value), do: is_binary(value) or is_number(value) or is_atom(value)

  defp matches?(value, where) do
    Enum.all?(where, fn {key, expected} ->
      case Map.fetch(value, key) do
        {:ok, actual} -> actual === expected
        :error -> false
      end
    end)
  end
end
