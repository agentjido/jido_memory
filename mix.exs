defmodule JidoMemory.MixProject do
  use Mix.Project

  @version "2.0.0"
  @source_url "https://github.com/agentjido/jido_memory"
  @description "Typed memory collections for Jido agents"

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
      package: package(),
      # Testing
      test_coverage: [tool: ExCoveralls, summary: [threshold: 0]]
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
      setup: ["deps.get"],
      "example.memory": ["run examples/00_start_here/00_02_answer_from_memory/run.exs"],
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
      {:jido, "== 3.0.0-beta.3"},
      # Dev & test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]}
    ]
  end

  defp docs do
    [
      extras: [
        "README.md",
        "CONTRIBUTING.md",
        "CHANGELOG.md",
        "guides/upgrading_to_2.md",
        "docs/plans/jido-v3-memory-dsl.md",
        "docs/examples-ladder.md"
      ],
      main: "readme",
      source_ref: "release/v3",
      # Jido generates these Plugin docs from hidden Agent.Extension callbacks.
      skip_code_autolink_to: ~w(
        c:Jido.Agent.Extension.decode_authoring_data/2
        c:Jido.Agent.Extension.derive_routes/1
        c:Jido.Agent.Extension.encode_authoring_data/2
        c:Jido.Agent.Extension.endpoint_kinds/0
        c:Jido.Agent.Extension.endpoints/1
        c:Jido.Agent.Extension.id/0
        c:Jido.Agent.Extension.verify/2
        c:Jido.Agent.Extension.verify_connection/2
        c:Jido.Agent.Extension.vsn/0
      ),
      formatters: ["html", "markdown"]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end
end
