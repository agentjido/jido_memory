Code.require_file(Path.expand("support/memory_agent_examples.exs", __DIR__))

alias Jido.Memory.Examples.Runner

IO.puts("Jido.Memory integration demo")
IO.puts("")

case Runner.run() do
  {:ok, %{plain_agent: plain_agent, ai_agent: ai_agent}} ->
    IO.puts("== Plain Jido agent ==")

    IO.inspect(
      %{
        agent_id: plain_agent.agent_id,
        namespace: plain_agent.namespace,
        retrieved_count: plain_agent.retrieved_count,
        retrieved_texts: plain_agent.retrieved_texts
      },
      pretty: true
    )

    IO.puts("")
    IO.puts("== AI-enabled Jido agent ==")

    IO.inspect(
      %{
        agent_id: ai_agent.agent_id,
        namespace: ai_agent.namespace,
        tool_name: ai_agent.tool_name,
        retrieved_count: ai_agent.retrieved_count,
        retrieved_texts: ai_agent.retrieved_texts
      },
      pretty: true
    )

  {:error, reason} ->
    IO.puts("Example failed: #{inspect(reason)}")
    System.halt(1)
end
