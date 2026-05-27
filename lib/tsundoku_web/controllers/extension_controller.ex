defmodule TsundokuWeb.ExtensionController do
  use TsundokuWeb, :controller

  alias Tsundoku.Accounts

  def show(conn, _params) do
    user = conn.assigns.current_user
    token = user |> Accounts.generate_user_session_token() |> Base.encode64()

    render(conn, :show, token: token, server_url: server_url(conn))
  end

  defp server_url(conn) do
    port_suffix =
      cond do
        conn.scheme == :http and conn.port == 80 -> ""
        conn.scheme == :https and conn.port == 443 -> ""
        true -> ":#{conn.port}"
      end

    "#{conn.scheme}://#{conn.host}#{port_suffix}"
  end
end
