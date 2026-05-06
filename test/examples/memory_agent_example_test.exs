Code.require_file(Path.expand("../../examples/support/memory_agent_examples.exs", __DIR__))

defmodule Jido.Memory.Examples.MemoryAgentExampleTest do
  use ExUnit.Case, async: false

  @moduletag :examples
  @jido_instance Jido.Memory.Examples.TestRuntime
  @plain_table :jido_memory_examples_agent
  @ai_table :jido_memory_examples_ai

  alias Jido.AgentServer
  alias Jido.AI.Actions.ToolCalling.ExecuteTool
  alias Jido.Memory.Examples.Actions.RetrieveNotes
  alias Jido.Memory.Examples.{AIEnabledAgent, JidoAgent}
  alias Jido.Memory.Runtime
  alias Jido.Memory.Store.ETS
  alias Jido.Signal

  setup do
    Application.ensure_all_started(:jido_signal)
    assert :ok = ETS.ensure_ready(table: @plain_table)
    assert :ok = ETS.ensure_ready(table: @ai_table)
    assert :ok = stop_jido_instance()
    assert {:ok, _pid} = Jido.start(name: @jido_instance, otp_app: :jido_memory)

    on_exit(fn -> :ok = stop_jido_instance() end)
    :ok
  end

  test "documented example modules prove plain and AI-enabled Jido agent integration" do
    plain_agent = exercise_plain_agent_example()
    ai_agent = exercise_ai_agent_example()

    assert plain_agent.plugin == Jido.Memory.BasicPlugin
    assert is_binary(plain_agent.namespace)
    assert String.starts_with?(plain_agent.namespace, "agent:")
    assert plain_agent.retrieved_count >= 1
    assert Enum.any?(plain_agent.retrieved_texts, &String.contains?(String.downcase(&1), "beam"))

    assert ai_agent.tool_name == "example_retrieve_notes"
    assert is_binary(ai_agent.namespace)
    assert String.starts_with?(ai_agent.namespace, "agent:")
    assert ai_agent.retrieved_count >= 1
    assert Enum.any?(ai_agent.retrieved_texts, &String.contains?(String.downcase(&1), "memory"))
    assert ai_agent.memory_result.retrieved_count == ai_agent.retrieved_count
    assert ai_agent.memory_result.retrieved_texts == ai_agent.retrieved_texts
    assert has_memory_plugin?(ai_agent.plugins)
  end

  defp exercise_plain_agent_example do
    agent_id = unique_agent_id("plain")

    assert {:ok, pid} = AgentServer.start_link(agent: JidoAgent, id: agent_id, jido: @jido_instance)

    try do
      assert {:ok, agent_state} = AgentServer.state(pid)
      agent = agent_state.agent

      assert {:ok, _record} = remember_note(agent, "The BEAM runs Elixir processes efficiently.")
      assert {:ok, _record} = remember_note(agent, "Phoenix uses PubSub for message fan-out.")

      signal = Signal.new!("demo.retrieve", %{query: "beam", limit: 5}, source: "/examples/plain")

      assert {:ok, retrieved_agent} = AgentServer.call(pid, signal)

      %{
        agent_id: agent_id,
        retrieved_count: retrieved_agent.state.retrieved_count,
        retrieved_texts: retrieved_agent.state.retrieved_texts,
        namespace: memory_namespace(retrieved_agent),
        plugin: Jido.Memory.BasicPlugin
      }
    after
      stop_server(pid)
    end
  end

  defp exercise_ai_agent_example do
    agent_id = unique_agent_id("ai")

    assert {:ok, pid} =
             AgentServer.start_link(agent: AIEnabledAgent, id: agent_id, jido: @jido_instance)

    try do
      assert {:ok, agent_state} = AgentServer.state(pid)
      agent = agent_state.agent

      assert {:ok, _record} =
               remember_note(agent, "Memories are stored in ETS and recalled through Jido.Memory.")

      assert {:ok, _record} =
               remember_note(agent, "The example AI agent exposes memory as a tool.")

      assert {:ok, tool_result} =
               Jido.Exec.run(
                 ExecuteTool,
                 %{
                   tool_name: RetrieveNotes.name(),
                   params: %{query: "memory", limit: 5}
                 },
                 %{
                   state: agent.state,
                   tools: [RetrieveNotes]
                 }
               )

      memory_result = tool_result.result

      %{
        agent_id: agent_id,
        tool_name: tool_result.tool_name,
        retrieved_count: Map.get(memory_result, :retrieved_count, 0),
        retrieved_texts: Map.get(memory_result, :retrieved_texts, []),
        memory_result: memory_result,
        namespace: memory_namespace(agent),
        plugins: AIEnabledAgent.plugins()
      }
    after
      stop_server(pid)
    end
  end

  defp has_memory_plugin?(plugins) when is_list(plugins) do
    Enum.any?(plugins, fn
      Jido.Memory.BasicPlugin -> true
      {Jido.Memory.BasicPlugin, _opts} -> true
      _other -> false
    end)
  end

  defp remember_note(agent, text) do
    Runtime.remember(agent, %{
      class: :semantic,
      kind: :fact,
      text: text,
      tags: ["example", "memory"]
    })
  end

  defp unique_agent_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}"
  end

  defp memory_namespace(%{state: %{__memory__: %{namespace: namespace}}}) when is_binary(namespace),
    do: namespace

  defp memory_namespace(_), do: nil

  defp stop_server(pid) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000), else: :ok
  end

  defp stop_jido_instance do
    case Process.whereis(@jido_instance) do
      nil ->
        :ok

      pid ->
        if Process.alive?(pid) do
          Process.unlink(pid)
          previous = Process.flag(:trap_exit, true)

          try do
            _ = Supervisor.stop(pid, :normal, 5_000)
          catch
            :exit, _reason -> :ok
          after
            Process.flag(:trap_exit, previous)
          end
        end

        :ok
    end
  end
end
