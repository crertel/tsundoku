# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :bookmark_server,
  ecto_repos: [BookmarkServer.Repo],
  generators: [binary_id: true]

config :bookmark_server, BookmarkServer.Repo, migration_timestamps: [type: :utc_datetime_usec]

# Configures the endpoint
config :bookmark_server, BookmarkServerWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "ztbf5nOym/gqsFjPl8HwVSiGwdQa4MKpjpsgI8u4EdyZaKBsg/WqDRIeFk9J40fm",
  render_errors: [
    formats: [html: BookmarkServerWeb.ErrorHTML, json: BookmarkServerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BookmarkServer.PubSub,
  live_view: [signing_salt: "MtF0gJXX"]

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
