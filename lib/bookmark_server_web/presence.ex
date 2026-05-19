defmodule BookmarkServerWeb.Presence do
  use Phoenix.Presence,
    otp_app: :bookmark_server,
    pubsub_server: BookmarkServer.PubSub
end
