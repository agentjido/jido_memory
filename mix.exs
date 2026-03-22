defmodule JidoMemory.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_memory"
  @description "Unified provider-backed memory system for Jido agents"

  def project do
    [
      app: :jido_memory,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      # Documentation
      name: "Jido Memory",
      source_url: @source_url,
      homepage_url: @source_url,
      description: @description,
      docs: docs(),
      # Testing
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "coveralls.html": :test,
        "test.watch": :test,
        quality: :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      setup: ["deps.get", "cmd npm install"],
      "test.acceptance": [
        "cmd env MIX_ENV=test mix test test/jido_memory/follow_on_acceptance_fixture_test.exs",
        "cmd env MIX_ENV=test mix test test/jido_memory/phase_03_integration_test.exs",
        "cmd env MIX_ENV=test mix test test/jido_memory/mirix_phase_03_integration_test.exs",
        "cmd env MIX_ENV=test mix test test/jido_memory/mirix_phase_04_integration_test.exs"
      ],
      quality: [
        "cmd env MIX_ENV=test mix format --check-formatted",
        "cmd env MIX_ENV=test mix credo --strict",
        "cmd env MIX_ENV=test mix dialyzer",
        "cmd env MIX_ENV=test mix test",
        "cmd env MIX_ENV=test mix test.acceptance",
        "cmd env MIX_ENV=test mix coveralls.html",
        "cmd env MIX_ENV=test mix spec.check"
      ]
    ]
  end

  defp deps do
    [
      # Jido ecosystem
      {:jido, "~> 2.1"},
      {:jido_action, "~> 2.1"},
      {:jido_ai, "~> 2.0"},
      # Validation & errors
      {:zoi, "~> 0.16"},
      {:splode, "~> 0.3"},
      {:postgrex, "~> 0.22", optional: true},
      # Dev & test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:doctor, "~> 0.21", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:mimic, "~> 2.0", only: :test},
      {:spec_led_ex, github: "specleddev/specled_ex", branch: "main", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      extras: [
        "README.md",
        "docs/guides/built_in_providers.md",
        "docs/guides/external_providers.md",
        "docs/guides/durable_long_term_storage.md",
        "docs/guides/follow_on_acceptance_matrix.md",
        "CONTRIBUTING.md",
        "CHANGELOG.md",
        "docs/rfcs/0001-canonical-memory-provider-architecture.md"
      ],
      main: "readme",
      source_ref: "main",
      formatters: ["html"]
    ]
  end
end
