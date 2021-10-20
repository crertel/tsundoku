defmodule BookmarkServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :bookmark_server,
      version: "0.1.0",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {BookmarkServer.Application, []},
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
      {:bcrypt_elixir, "~> 2.0"},
      {:cors_plug, "~> 2.0"},
      {:ecto_sql, "~> 3.7.1"},
      {:floki, "~> 0.32.0"},
      {:heroicons, "~>0.2.4"},
      {:jason, "~> 1.0"},
      {:phoenix_ecto, "~> 4.4.0"},
      {:phoenix_html, "~> 3.0.4"},
      {:phoenix_live_dashboard, "~> 0.5.3"},
      {:phoenix_live_reload, "~> 1.3.3", only: :dev},
      {:phoenix_live_view, "~> 0.16.4"},
      {:phoenix, "~> 1.6.2"},
      {:plug_cowboy, "~> 2.5.2"},
      {:postgrex, "0.15.12"},
      {:scrivener_ecto, "~> 2.7.0"},
      {:telemetry_metrics, "~> 0.6.1"},
      {:telemetry_poller, "~> 1.0.0"},
      {:valid_url, "~> 0.1.2"},
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
      setup: ["deps.get", "ecto.setup", "cmd npm install --prefix assets"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
