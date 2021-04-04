# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :bookmark_server,
  ecto_repos: [BookmarkServer.Repo],
  generators: [binary_id: true]

config :bookmark_server, BookmarkServer.Repo, migration_timestamps: [type: :utc_datetime]

# Configures the endpoint
config :bookmark_server, BookmarkServerWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "ztbf5nOym/gqsFjPl8HwVSiGwdQa4MKpjpsgI8u4EdyZaKBsg/WqDRIeFk9J40fm",
  render_errors: [view: BookmarkServerWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: BookmarkServer.PubSub,
  live_view: [signing_salt: "MtF0gJXX"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
