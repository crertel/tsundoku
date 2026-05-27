defmodule TsundokuWeb.Plugs.TokenAccess do
  import Plug.Conn
  alias Tsundoku.Accounts

  def init(default), do: default

  def call(conn, _) do
    with [raw_header] <- get_req_header(conn, "authorization"),
         [scheme, encoded_token] <- String.split(raw_header, " ", parts: 2),
         true <- String.downcase(scheme) == "bearer",
         {:ok, token} <- Base.decode64(encoded_token, ignore: :whitespace),
         user when not is_nil(user) <- Accounts.get_user_by_session_token(token) do
      assign(conn, :user, user)
    else
      _ ->
        conn |> send_resp(403, "{}") |> halt()
    end
  end
end
