import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :bookmark_server, BookmarkServer.Repo,
  username: "postgres",
  password: "postgres",
  database: "bookmark_server_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bookmark_server, BookmarkServerWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Oban jobs are enqueued but not executed during tests. Tests that want
# to drive a job to completion call `Oban.drain_queue/1` explicitly.
config :bookmark_server, Oban, testing: :manual
