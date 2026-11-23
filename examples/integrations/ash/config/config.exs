import Config

config :ash, default_string_length_count: :codepoints

config :logger, level: :warning

if System.get_env("MEMORY_ARCANA") == "1" do
  config :arcana, embedder: {SupportDesk.GuideEmbedder, []}
end

config :jido_memory_ash_examples,
  ash_domains: [
    JidoMemory.Examples.Ash.Accounts,
    JidoMemory.Examples.Ash.Refunds,
    JidoMemory.Examples.Ash.MemoryRecords,
    JidoMemory.Examples.Ash.Articles
  ]
