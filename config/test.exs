import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :tsundoku, Tsundoku.Repo,
  username: "postgres",
  password: "postgres",
  database: "tsundoku_test#{System.get_env("MIX_TEST_PARTITION")}",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tsundoku, TsundokuWeb.Endpoint,
  http: [port: 4002],
  server: false,
  secret_key_base: "test_secret_key_base_at_least_64_bytes_long_for_phoenix_to_accept_it___",
  live_view: [signing_salt: "test-salt"]

# Logger level is set at runtime by config/runtime.exs (LOG_LEVEL env var,
# defaults to :warning in test).

# Crawler tests exercise failures; don't sit through Req's retry backoff.
config :tsundoku, :metadata_req_options, retry: false

# Queues don't run in tests, so there is nothing to push saved crawl
# settings to at boot.
config :tsundoku, :apply_crawl_settings_on_boot, false

# Oban jobs are enqueued but not executed during tests. Tests that want
# to drive a job to completion call `Oban.drain_queue/1` explicitly.
config :tsundoku, Oban, testing: :manual
