defmodule JidoMemory.Examples.MemPalace.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_memory_mempalace_examples,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: source_paths(),
      deps: [
        {:jido_memory, path: "../../.."},
        {:ecto_sql, "~> 3.14"},
        {:ecto_sqlite3, "~> 0.26.0"},
        {:postgrex, "~> 0.22.0"},
        {:zoi, "~> 0.19.0"}
      ]
    ]
  end

  # The MemPalace service still refers to the old provider data types.
  # Compile those types from the provider's pinned legacy dependency.
  defp source_paths do
    models =
      ~w(helpers record query hit ingest_request ingest_result capabilities capability_set
         provider_info provider_registry provider scope explanation retrieve_result consolidation_result)

    palace = System.get_env("MEMORY_MEMPALACE_PATH", Path.expand("../../../../jido_memory_mempalace", __DIR__))
    source = Path.join(palace, "lib/jido/memory")
    legacy = Path.join(palace, "deps/jido_memory/lib/jido_memory")

    if !File.dir?(Path.join(source, "mem_palace")) do
      Mix.raise("Set MEMORY_MEMPALACE_PATH to the jido_memory_mempalace checkout.")
    end

    if !File.regular?(Path.join(legacy, "record.ex")) do
      Mix.raise("Run mix deps.get in the jido_memory_mempalace checkout first.")
    end

    [
      "lib",
      Path.join(source, "mem_palace"),
      Path.join(source, "mem_palace.ex"),
      Path.join(source, "provider/mem_palace.ex"),
      Path.join(legacy, "capability")
      | Enum.map(models, &Path.join(legacy, &1 <> ".ex"))
    ]
  end
end
