defmodule BookmarkServerWeb.Plugs.TokenAccess do
  import Plug.Conn
  alias BookmarkServer.Accounts

  def init(default), do: default

  def call(conn, _) do
    with {:get_header, [raw_header]} <- {:get_header, get_req_header(conn, "authorization")},
         {:parse_header, ["bearer", encoded_token]} <-
           {:parse_header, raw_header |> String.split()},
         {:decode_token, {:ok, token}} <-
           {:decode_token, Base.decode64(encoded_token, ignore: :whitespace)} do
      IO.inspect( {token, encoded_token}, label: "MMMMMMM")
      user = Accounts.get_user_by_session_token(token)
      assign(conn, :user, user)
    else
      _ ->
        conn |> put_status(403) |> halt
    end
  end
end
