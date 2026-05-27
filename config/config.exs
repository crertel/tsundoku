# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tsundoku,
  ecto_repos: [Tsundoku.Repo],
  generators: [binary_id: true]

config :tsundoku, Tsundoku.Repo, migration_timestamps: [type: :utc_datetime_usec]

config :tsundoku, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  # Queue concurrency: 5 workers can run in parallel, but per-domain
  # serialization is enforced inside the worker via DomainMutex so we
  # never hit the same host concurrently.
  queues: [metadata: 5],
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}],
  repo: Tsundoku.Repo

# Configures the endpoint. secret_key_base and live_view.signing_salt are
# per-env: dev/test set them in their own config files; prod reads them from
# runtime.exs.
config :tsundoku, TsundokuWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: TsundokuWeb.ErrorHTML, json: TsundokuWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Tsundoku.PubSub

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure esbuild (the version is required)
config :esbuild,
  version: System.get_env("MIX_ESBUILD_VERSION", "0.25.1"),
  path: System.get_env("MIX_ESBUILD_PATH"),
  default: [
    args: ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: System.get_env("MIX_TAILWIND_VERSION", "3.4.17"),
  path: System.get_env("MIX_TAILWIND_PATH"),
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
