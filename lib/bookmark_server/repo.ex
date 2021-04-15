defmodule BookmarkServer.Repo do
  use Ecto.Repo,
    otp_app: :bookmark_server,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 30
end
