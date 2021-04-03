defmodule BookmarkServer.Repo do
  use Ecto.Repo,
    otp_app: :bookmark_server,
    adapter: Ecto.Adapters.Postgres
end
