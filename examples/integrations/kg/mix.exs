defmodule JidoMemory.Examples.KG.MixProject do
  use Mix.Project

  @triple_store_ref "6dc1b6d985f4805f9856858e0c0047b9f2d5ad7f"

  def project do
    [
      app: :jido_memory_kg_examples,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [{:jido_memory, path: "../../.."}, triple_store()]
    ]
  end

  defp triple_store do
    case System.get_env("TRIPLE_STORE_PATH") do
      nil -> {:triple_store, github: "pcharbon70/triple_store", ref: @triple_store_ref}
      path -> {:triple_store, path: path}
    end
  end
end
