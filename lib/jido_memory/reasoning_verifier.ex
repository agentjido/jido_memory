defmodule Jido.Memory.ReasoningVerifier do
  @moduledoc false

  use Spark.Dsl.Verifier

  alias Jido.AI.Agent.Plugin, as: AIPlugin
  alias Jido.AI.Reasoning.Actions.{CallModel, ProjectConversation}
  alias Jido.Flow
  alias Jido.Flow.{Component, Ref}
  alias Jido.Instruction
  alias Jido.Memory.Actions.{Access, RecallForModel, RecallGranted}
  alias Jido.Memory.Plugin
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    agent = Verifier.get_persisted(dsl, :module)

    with true <- Verifier.get_option(dsl, [:memory], :warn_unwired_reasoning, true),
         {:ok, %{plugins: plugins}} <- agent.__jido_definition__(related?: true),
         %{reasoning: reasoning} <- plugin_data(plugins, AIPlugin),
         %{} = memory <- plugin_data(plugins, Plugin),
         true <- function_exported?(reasoning, :flow, 0),
         %Flow{} = flow <- reasoning.flow(),
         message when is_binary(message) <- wiring_problem(flow, reasoning, memory) do
      warning(dsl, agent, reasoning, message)
    else
      _ -> :ok
    end
  end

  defp plugin_data(plugins, provider) do
    Enum.find_value(plugins, fn
      %{provider: ^provider, data: data} -> data
      _ -> nil
    end)
  end

  defp action_calls(flow) do
    for {name, component} <- flow.components,
        {_slot, %{kind: :action, target: action}, params} <- Component.calls(component),
        action in [RecallForModel, RecallGranted, Access, CallModel] do
      {name, action, params}
    end
  end

  defp wiring_problem(flow, reasoning, memory) do
    {model_calls, memory_calls} = Enum.split_with(action_calls(flow), &match?({_, CallModel, _}, &1))

    if memory_calls == [] do
      "This reasoning Flow has no recognized memory step. " <>
        "Add RecallForModel, RecallGranted, or Access. Set warn_unwired_reasoning false for deliberate manual use."
    else
      first_literal_problem(memory_calls, reasoning, memory) || context_problem(flow, memory_calls, model_calls)
    end
  end

  defp first_literal_problem(calls, reasoning, memory) do
    calls
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.find_value(fn {name, action, params} ->
      if problem = literal_problem(action, params, reasoning, memory) do
        "The step #{inspect(name)} #{problem}"
      end
    end)
  end

  defp literal_problem(action, %{enabled: false}, _reasoning, _memory)
       when action in [RecallForModel, RecallGranted],
       do: nil

  defp literal_problem(action, %{grant: grant} = params, reasoning, memory)
       when action in [RecallForModel, RecallGranted] and is_atom(grant) do
    case memory do
      %{flow: bound_flow} when bound_flow != reasoning ->
        "uses read grant #{inspect(grant)}. The grants are bound to #{inspect(bound_flow)}. " <>
          "Bind the read grant to the reasoning Flow."

      _ ->
        case get_in(memory, [:reads, grant]) do
          nil -> "uses unknown read grant #{inspect(grant)}. Use or declare a read grant for this reasoning Flow."
          %{filters: filters} -> filter_problem(params[:where], grant, filters)
        end
    end
  end

  defp literal_problem(Access, %{kind: kind, name: name, operation: operation}, _reasoning, memory)
       when is_atom(kind) and is_atom(name) and is_atom(operation) do
    case get_in(memory, [:bindings, kind, name]) do
      nil ->
        "uses unknown memory #{kind} #{inspect(name)}. Use or declare a named memory binding."

      operations ->
        case Map.fetch(operations, operation) do
          {:ok, target} ->
            if match?({:ok, %{kind: :flow}}, Instruction.resolve(target)) do
              "uses #{inspect(operation)} on memory #{kind} #{inspect(name)}. Access requires an Action. " <>
                "Use invoke or handoff for the bound Flow #{inspect(target)}."
            end

          :error ->
            "uses memory #{kind} #{inspect(name)}, which does not declare operation #{inspect(operation)}. " <>
              "Use or declare that operation on the binding."
        end
    end
  end

  defp literal_problem(_action, _params, _reasoning, _memory), do: nil

  defp filter_problem(where, grant, filters) when is_map(where) and not is_struct(where) do
    case Enum.sort(Map.keys(where) -- filters) do
      [] -> nil
      keys -> "uses filter keys #{inspect(keys)} outside read grant #{inspect(grant)}. Use filters from the grant."
    end
  end

  defp filter_problem(_where, _grant, _filters), do: nil

  defp context_problem(flow, memory_calls, [{model, CallModel, %{context: model_context}}]) do
    recalls = for {_, RecallForModel, _} = call <- memory_calls, do: call

    with [{recall, RecallForModel, %{context: ^model_context} = params}] <- recalls,
         true <- Map.get(params, :enabled, true) == true,
         %Ref{source: :result, component: project, path: [:context]} <- model_context,
         %{kind: :call, call: %{target: ProjectConversation}} <- flow.components[project],
         true <-
           Enum.all?(flow.components, fn {_, component} -> match?(%{kind: :call, call: %{kind: :action}}, component) end),
         {:ok, dependencies} <- Flow.dependencies(flow),
         false <- reads_result?([model], recall, dependencies, MapSet.new()) do
      "The step #{inspect(model)} bypasses the context from step #{inspect(recall)}. " <>
        "Pass the recall context or build the model context from the recalled records."
    else
      _ -> nil
    end
  end

  defp context_problem(_flow, _memory_calls, _model_calls), do: nil

  defp reads_result?([], _source, _dependencies, _visited), do: false
  defp reads_result?([source | _], source, _dependencies, _visited), do: true

  defp reads_result?([step | remaining], source, dependencies, visited) do
    if MapSet.member?(visited, step) do
      reads_result?(remaining, source, dependencies, visited)
    else
      %{references: references} = Map.fetch!(dependencies, step)
      reads_result?(references ++ remaining, source, dependencies, MapSet.put(visited, step))
    end
  end

  defp warning(dsl, agent, reasoning, message) do
    annotation = agent.section_anno([:memory]) || :erl_anno.new(1)
    file = Verifier.get_persisted(dsl, :file)
    location = :erl_anno.set_file(String.to_charlist(file), annotation)

    {:warn, {"[Jido.Memory] Agent #{inspect(agent)}, reasoning Flow #{inspect(reasoning)}. #{message}", location}}
  end
end
