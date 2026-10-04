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
      crawl_settings_child(),
      TsundokuWeb.Presence,
      TsundokuWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tsundoku.Supervisor]
    children = Enum.reject(children, &is_nil/1)
    Supervisor.start_link(children, opts)
  end

  # Saved crawl settings (concurrency, paused) aren't part of the Oban
  # config, so push them to the queue once it has started. Off in the
  # test env, where queues don't run.
  defp crawl_settings_child do
    if Application.get_env(:tsundoku, :apply_crawl_settings_on_boot, true) do
      Supervisor.child_spec({Task, &Tsundoku.Crawl.apply_saved_settings/0}, restart: :temporary)
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    TsundokuWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
