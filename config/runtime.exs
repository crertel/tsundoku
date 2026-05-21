import Config

# config/runtime.exs runs after the release boots, so this is where all
# env-var-driven config belongs. Anything that needs to be different
# between machines (DB URL, secret, port, host) goes here.

defmodule BookmarkServer.RuntimeConfigHelpers do
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

alias BookmarkServer.RuntimeConfigHelpers, as: H

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :bookmark_server, BookmarkServer.Repo,
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

  config :bookmark_server, BookmarkServerWeb.Endpoint,
    server: true,
    url: [host: host, port: url_port, scheme: scheme],
    http: [
      ip: H.parse_ip(System.get_env("PHX_LISTEN_IP") || "0.0.0.0"),
      port: port
    ],
    secret_key_base: secret_key_base,
    check_origin: H.parse_check_origin(System.get_env("PHX_CHECK_ORIGIN"))
end
