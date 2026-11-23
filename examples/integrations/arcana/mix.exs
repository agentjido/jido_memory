defmodule JidoMemory.Examples.Arcana.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_memory_arcana_examples,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [{:jido_memory, path: "../../.."}, {:arcana, "4.0.3"}]
    ]
  end
end
