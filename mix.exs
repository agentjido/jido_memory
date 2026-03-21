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
      # Documentation
      name: "Jido Memory",
      source_url: @source_url,
      homepage_url: @source_url,
      description: @description,
      docs: docs(),
      # Testing
      test_coverage: [tool: :coveralls],
      preferred_cli_env: [
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

  defp deps do
    [
      # Jido ecosystem
      {:jido, "~> 2.1"},
      {:jido_action, "~> 2.1"},
      {:jido_ai, "~> 2.0"},
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
      {:mimic, "~> 2.0", only: :test},
      {:spec_led_ex,
       github: "specleddev/specled_ex", branch: "main", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      extras: [
        "README.md",
        "CONTRIBUTING.md",
        "CHANGELOG.md"
      ],
      main: "readme",
      source_ref: "main",
      formatters: ["html"]
    ]
  end
end
