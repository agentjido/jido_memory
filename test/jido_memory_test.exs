defmodule JidoMemoryTest do
  use ExUnit.Case
  doctest JidoMemory

  test "greets the world" do
    assert JidoMemory.hello() == :world
  end
end
