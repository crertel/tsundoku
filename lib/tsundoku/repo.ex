defmodule Tsundoku.Repo do
  use Ecto.Repo,
    otp_app: :tsundoku,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 200
end
