import Config

config :logger, level: :warning
config :arcana, embedder: {SupportDesk.GuideEmbedder, []}
