defmodule TsundokuWeb.Presence do
  use Phoenix.Presence,
    otp_app: :tsundoku,
    pubsub_server: Tsundoku.PubSub
end
