defmodule JidoMemory.Examples.Ash.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_memory_ash_examples,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps:
        [
          {:jido_memory, path: "../../.."},
          {:ash_jido, path: ash_jido_path()},
          {:simple_sat, "~> 0.1"}
        ] ++ arcana()
    ]
  end

  defp arcana do
    if System.get_env("MEMORY_ARCANA") == "1" do
      [{:jido_memory_arcana_examples, path: "../arcana"}]
    else
      []
    end
  end

  defp ash_jido_path do
    System.get_env("ASH_JIDO_PATH") ||
      Path.expand("../../../../../jido_adapters/ash_jido", __DIR__)
  end
end
