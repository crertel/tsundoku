defmodule Tsundoku.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      Tsundoku.Repo,
      TsundokuWeb.Telemetry,
      {Phoenix.PubSub, name: Tsundoku.PubSub},
      Tsundoku.DomainMutex,
      {Oban, Application.fetch_env!(:tsundoku, Oban)},
      TsundokuWeb.Presence,
      TsundokuWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tsundoku.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    TsundokuWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
