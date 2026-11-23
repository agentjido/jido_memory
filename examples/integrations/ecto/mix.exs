defmodule JidoMemory.Examples.Ecto.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_memory_ecto_examples,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [
        {:jido_memory, path: "../../.."},
        {:ecto_sql, "~> 3.14"},
        {:ecto_sqlite3, "~> 0.26.0"},
        {:postgrex, "~> 0.22.0"}
      ]
    ]
  end
end
