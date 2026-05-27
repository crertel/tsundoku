import Config

# config/runtime.exs runs after the release boots, so this is where all
# env-var-driven config belongs. Anything that needs to be different
# between machines (DB URL, secret, port, host) goes here.

defmodule Tsundoku.RuntimeConfigHelpers do
  @moduledoc false

  def read_secret(name) do
    case System.get_env(name) do
      val when is_binary(val) and val != "" ->
        val

      _ ->
        case System.get_env(name <> "_FILE") do
          nil -> nil
          path -> path |> File.read!() |> String.trim()
        end
    end
  end

  def maybe_ipv6(val) when val in [nil, "", "0", "false"], do: []
  def maybe_ipv6(_), do: [:inet6]

  def parse_ip(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, parsed} -> parsed
      _ -> {0, 0, 0, 0}
    end
  end

  def parse_check_origin(val) when val in [nil, ""], do: ["//localhost"]
  def parse_check_origin("*"), do: true

  def parse_check_origin(csv) do
    csv |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end
end

alias Tsundoku.RuntimeConfigHelpers, as: H

# --- Cross-env runtime knobs --------------------------------------------
# Apply in dev, test, and prod (anything you can twist without rebuilding).

log_level_default =
  case config_env() do
    :prod -> "info"
    :test -> "warning"
    :dev -> "debug"
  end

log_level =
  (System.get_env("LOG_LEVEL") || log_level_default)
  |> String.downcase()
  |> String.to_existing_atom()

config :logger, level: log_level

if val = System.get_env("OBAN_METADATA_CONCURRENCY") do
  config :tsundoku, Oban, queues: [metadata: String.to_integer(val)]
end

if val = System.get_env("OBAN_PRUNE_MAX_AGE_DAYS") do
  config :tsundoku, Oban,
    plugins: [{Oban.Plugins.Pruner, max_age: String.to_integer(val) * 24 * 60 * 60}]
end

# --- Prod-only runtime config ------------------------------------------

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :tsundoku, Tsundoku.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: H.maybe_ipv6(System.get_env("ECTO_IPV6"))

  secret_key_base =
    H.read_secret("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE (or SECRET_KEY_BASE_FILE pointing
      at a file containing it) is missing. Generate with: mix phx.gen.secret
      """

  port = String.to_integer(System.get_env("PORT") || "4000")
  host = System.get_env("PHX_HOST") || "localhost"
  scheme = System.get_env("PHX_SCHEME") || "http"

  url_port =
    case System.get_env("PHX_URL_PORT") do
      nil -> if scheme == "https", do: 443, else: port
      val -> String.to_integer(val)
    end

  config :tsundoku, TsundokuWeb.Endpoint,
    server: true,
    url: [host: host, port: url_port, scheme: scheme],
    http: [
      ip: H.parse_ip(System.get_env("PHX_LISTEN_IP") || "0.0.0.0"),
      port: port
    ],
    secret_key_base: secret_key_base,
    check_origin: H.parse_check_origin(System.get_env("PHX_CHECK_ORIGIN"))
end
