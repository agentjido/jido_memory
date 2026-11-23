defmodule Jido.Memory.DSL do
  @moduledoc "Defines the memory declarations for a Jido Agent."

  alias Jido.Error
  alias Spark.Dsl.Extension

  defmodule Collection do
    @moduledoc false
    defstruct [:name, :schema, :max_entries, :store, :__spark_metadata__]

    @type t :: %__MODULE__{
            name: atom(),
            schema: Jido.Joi.schema(),
            max_entries: pos_integer() | nil,
            store: {module(), map()} | nil
          }
  end

  defmodule Read do
    @moduledoc false
    defstruct [:name, :collection, :filters, :expose, :limit, :__spark_metadata__]

    @type t :: %__MODULE__{
            name: atom(),
            collection: atom(),
            filters: [atom()],
            expose: [atom()],
            limit: pos_integer()
          }
  end

  defmodule Binding do
    @moduledoc false
    defstruct [:kind, :name, :operations, :__spark_metadata__]

    @type t :: %__MODULE__{kind: :source | :index | :graph, name: atom(), operations: keyword(module())}
  end

  @collection %Spark.Dsl.Entity{
    name: :__collection__,
    target: Collection,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      schema: [type: :any, required: true],
      max_entries: [type: :pos_integer, required: true]
    ]
  }
  @external_collection %Spark.Dsl.Entity{
    name: :__external_collection__,
    target: Collection,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      schema: [type: :any, required: true],
      store: [type: :any, required: true]
    ]
  }
  @read %Spark.Dsl.Entity{
    name: :read,
    target: Read,
    args: [:name],
    schema: [
      name: [type: :atom, required: true],
      collection: [type: :atom, required: true],
      filters: [type: {:list, :atom}, default: []],
      expose: [type: {:list, :atom}, required: true],
      limit: [type: :pos_integer, required: true]
    ]
  }
  @bindings (for kind <- [:source, :index, :graph] do
               %Spark.Dsl.Entity{
                 name: kind,
                 target: Binding,
                 args: [:name],
                 auto_set_fields: [kind: kind],
                 schema: [
                   name: [type: :atom, required: true],
                   operations: [type: :keyword_list, required: true]
                 ]
               }
             end)

  @memory %Spark.Dsl.Section{
    name: :memory,
    schema: [bound_flow: [type: :atom], warn_unwired_reasoning: [type: :boolean, default: true]],
    entities: [@collection, @external_collection, @read | @bindings],
    imports: [__MODULE__]
  }
  @collection_entity Module.concat([Jido.Memory.Plugin, Memory, Macro.camelize("__collection__")])
  @external_collection_entity Module.concat([Jido.Memory.Plugin, Memory, Macro.camelize("__external_collection__")])

  @doc false
  @spec section() :: Spark.Dsl.Section.t()
  def section, do: @memory

  @doc "Declares collections and read grants for an Agent's root Flow."
  defmacro memory(flow, do: block) do
    quote do
      require Jido.Memory.Plugin

      Jido.Memory.Plugin.memory do
        bound_flow(unquote(flow))
        unquote(block)
      end
    end
  end

  @doc false
  defmacro collection(name, opts, body),
    do: collection_ast(@collection_entity, :__collection__, name, opts, body)

  @doc false
  defmacro external_collection(name, opts, body),
    do: collection_ast(@external_collection_entity, :__external_collection__, name, opts, body)

  defp collection_ast(entity, declaration, name, opts, do: {:schema, _, [schema]}) when is_list(opts) do
    quote do
      require unquote(entity)
      unquote(entity).unquote(declaration)(unquote(name), unquote(Keyword.put(opts, :schema, schema)))
    end
  end

  defp collection_ast(_entity, _declaration, _name, _opts, _body),
    do: raise(ArgumentError, "A memory collection requires a single schema declaration")

  @doc false
  @spec lower(map(), map()) :: {:ok, map()} | {:error, Jido.Error.ValidationError.t()}
  def lower(dsl, config) do
    declarations = Extension.get_entities(dsl, [:memory])
    flow = Extension.get_opt(dsl, [:memory], :bound_flow)

    case {declarations, flow} do
      {[], nil} -> {:ok, config}
      _ when config == %{} -> lower_declarations(declarations, flow)
      _ -> invalid_config("Use the memory block or explicit memory configuration")
    end
  end

  defp lower_declarations(declarations, flow) do
    {bindings, declarations} = Enum.split_with(declarations, &match?(%Binding{}, &1))
    {collections, reads} = Enum.split_with(declarations, &match?(%Collection{}, &1))

    with {:ok, collections} <- index_declarations(collections, [:schema, :max_entries, :store], "collection"),
         {:ok, reads} <- index_declarations(reads, [:collection, :filters, :expose, :limit], "read"),
         {:ok, bindings} <- lower_bindings(bindings) do
      config = %{collections: collections}
      config = if map_size(bindings) == 0, do: config, else: Map.put(config, :bindings, bindings)

      case {flow, reads} do
        {nil, reads} when map_size(reads) == 0 -> {:ok, config}
        _ -> {:ok, Map.merge(config, %{flow: flow, reads: reads})}
      end
    end
  end

  defp index_declarations(declarations, fields, label) do
    entries =
      Map.new(declarations, fn declaration ->
        data = Map.take(declaration, fields)

        data =
          case declaration do
            %Collection{store: nil} -> Map.delete(data, :store)
            %Collection{} -> Map.delete(data, :max_entries)
            %Read{} -> data
          end

        {declaration.name, data}
      end)

    if map_size(entries) == length(declarations),
      do: {:ok, entries},
      else: invalid_config("Memory #{label} names must be unique")
  end

  defp lower_bindings(bindings) do
    Enum.reduce_while(bindings, {:ok, %{}}, fn %{kind: kind, name: name, operations: operations}, {:ok, all} ->
      named = Map.get(all, kind, %{})
      by_operation = Map.new(operations)

      cond do
        Map.has_key?(named, name) ->
          {:halt, invalid_config("Duplicate memory #{kind} #{inspect(name)}")}

        map_size(by_operation) != length(operations) ->
          {:halt, invalid_config("Duplicate operation for memory #{kind} #{inspect(name)}")}

        true ->
          {:cont, {:ok, Map.put(all, kind, Map.put(named, name, by_operation))}}
      end
    end)
  end

  defp invalid_config(message), do: {:error, Error.validation_error(message, path: [:memory])}
end
