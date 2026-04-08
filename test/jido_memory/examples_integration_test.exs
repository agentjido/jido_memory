Code.require_file(Path.expand("../../examples/support/memory_agent_examples.exs", __DIR__))

defmodule Jido.Memory.ExamplesIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Memory.Examples.Runner

  test "plain Jido agent recalls stored notes through the memory plugin" do
    assert {:ok, result} = Runner.run_plain_agent_demo()
    assert result.plugin == Jido.Memory.ETSPlugin
    assert is_binary(result.namespace)
    assert String.starts_with?(result.namespace, "agent:")
    assert result.recalled_count >= 1
    assert Enum.any?(result.recalled_texts, &String.contains?(String.downcase(&1), "beam"))
  end

  test "AI-enabled Jido agent exposes memory recall as a tool" do
    assert {:ok, result} = Runner.run_ai_agent_demo()
    assert result.tool_name == "example_recall_notes"
    assert is_binary(result.namespace)
    assert String.starts_with?(result.namespace, "agent:")
    assert result.recalled_count >= 1
    assert Enum.any?(result.recalled_texts, &String.contains?(String.downcase(&1), "memory"))
    assert result.memory_result.recalled_count == result.recalled_count
    assert result.memory_result.recalled_texts == result.recalled_texts
    assert has_memory_plugin?(result.plugins)
  end

  defp has_memory_plugin?(plugins) when is_list(plugins) do
    Enum.any?(plugins, fn
      Jido.Memory.ETSPlugin -> true
      {Jido.Memory.ETSPlugin, _opts} -> true
      _other -> false
    end)
  end
end
