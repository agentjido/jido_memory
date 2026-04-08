defmodule JidoMemory.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_memory"
  @description "Data-driven, ETS-backed memory system for Jido agents"

  def project do
    [
      app: :jido_memory,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      cli: cli(),
      # Documentation
      name: "Jido Memory",
      source_url: @source_url,
      homepage_url: @source_url,
      description: @description,
      docs: docs(),
      # Testing
      test_coverage: [summary: [threshold: 0]]
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
      "example.memory": ["run examples/memory_agent_demo.exs"],
      quality: [
        "format",
        "credo --strict",
        "dialyzer",
        "test",
        "coveralls.html",
        "doctor --raise"
      ]
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

  defp deps do
    [
      # Jido ecosystem
      {:jido, "~> 2.0.0-rc.5"},
      {:jido_action, "~> 2.0", override: true},
      {:jido_ai, "== 2.0.0-rc.0"},
      # `tzdata` currently pulls an older `hackney` that expects these Erlang apps
      # to be present at runtime but does not bring them into this Mix lock path.
      {:mimerl, "~> 1.0"},
      {:certifi, "~> 0.7.0"},
      {:ssl_verify_fun, "~> 1.1"},
      {:metrics, "~> 1.0"},
      # Validation & errors
      {:zoi, "~> 0.16"},
      {:splode, "~> 0.3"},
      # Dev & test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:doctor, "~> 0.21", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:mimic, "~> 2.0", only: :test}
    ]
  end

  defp docs do
    [
      extras: [
        "README.md",
        "CONTRIBUTING.md",
        "CHANGELOG.md",
        "docs/provider_contract.md",
        "docs/provider_migration.md"
      ],
      main: "readme",
      source_ref: "main",
      formatters: ["html"]
    ]
  end
end
