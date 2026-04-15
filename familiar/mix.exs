defmodule Familiar.MixProject do
  use Mix.Project

  def project do
    [
      app: :familiar,
      version: "0.1.0",
      elixir: "~> 1.15",
      description:
        "AI agent platform that autonomously builds institutional memory about codebases",
      package: [
        licenses: ["AGPL-3.0-only"],
        links: %{}
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [threshold: 90],
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        flags: [:error_handling, :underspecs]
      ],
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      escript: escript(),
      releases: releases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  defp escript do
    [
      main_module: Familiar.CLI.Main,
      name: "fam"
    ]
  end

  defp releases do
    [
      familiar: [
        include_executables_for: [:unix],
        overlays: ["rel/overlays"]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Familiar.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # Familiar-specific dependencies
      {:sqlite_vec, "~> 0.1.0"},
      {:req, "~> 0.5"},
      {:mox, "~> 1.0", only: :test},
      {:stream_data, "~> 1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:boundary, "~> 0.10"},
      {:toml, "~> 0.7"},
      {:yaml_elixir, "~> 2.9"},
      {:file_system, "~> 1.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["compile", "esbuild familiar"],
      "assets.deploy": [
        "esbuild familiar --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "sobelow --config",
        "test",
        "dialyzer"
      ]
    ]
  end
end
