defmodule Tsundoku.MixProject do
  use Mix.Project

  def project do
    [
      app: :tsundoku,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      test_coverage: test_coverage()
    ]
  end

  # Mix tasks, release tasks, and test support aren't exercised by the
  # suite; leaving them in drags the total down without telling us anything.
  defp test_coverage do
    [
      ignore_modules: [
        ~r/^Mix\.Tasks\./,
        Tsundoku.Release,
        Tsundoku.AccountsFixtures,
        Tsundoku.DataCase,
        Tsundoku.MetadataServer,
        TsundokuWeb.ChannelCase,
        TsundokuWeb.ConnCase
      ]
    ]
  end

  defp releases do
    [
      tsundoku: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Tsundoku.Application, []},
      extra_applications: [:logger, :runtime_tools]
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
      {:bcrypt_elixir, "~> 3.3.2"},
      {:cors_plug, "~> 3.0.3"},
      {:ecto_sql, "~> 3.14.0"},
      {:elixir_make, "~> 0.10"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:floki, "~> 0.38.4"},
      {:heroicons, "~> 0.5.7"},
      {:jason, "~> 1.4.1"},
      {:lazy_html, ">= 0.1.13", only: :test},
      {:oban, "~> 2.24"},
      {:oban_web, "~> 2.13"},
      {:phoenix_ecto, "~> 4.7.0"},
      {:phoenix_html, "~> 4.3.0"},
      {:phoenix_live_dashboard, "~> 0.9.1"},
      {:phoenix_live_reload, "~> 1.7.0", only: :dev},
      {:phoenix_live_view, "~> 1.2.12"},
      {:phoenix_html_helpers, "~> 1.0"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix, "~> 1.8.15"},
      {:plug_cowboy, "~> 2.9.0"},
      {:postgrex, "~> 0.22.4"},
      {:req, "~> 0.7"},
      {:scrivener_ecto, "~> 3.1.0"},
      {:tailwind, "~> 0.5.1", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.2.0"},
      {:telemetry_poller, "~> 1.3.0"},
      {:valid_url, "~> 0.1.2"}
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
      setup: ["deps.get", "ecto.setup", "assets.static"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.static": &copy_static_assets/1,
      "assets.deploy": [
        "assets.static",
        "extension.build",
        "tailwind default --minify",
        "esbuild default --minify",
        "phx.digest"
      ]
    ]
  end

  defp copy_static_assets(_args) do
    File.cp_r!("assets/static", "priv/static")
  end
end
