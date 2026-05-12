defmodule BookmarkServerWeb.UserTokenController do
  use BookmarkServerWeb, :controller

  alias BookmarkServer.Accounts

  def new(conn, %{"username" => username, "password" => password}) do
    with {:user, user} when user != nil <-
           {:user, Accounts.get_user_by_email_and_password(username, password)},
         {:token, token} when token != nil <- {:token, Accounts.generate_user_session_token(user)} do
      conn
      |> put_status(201)
      |> json(%{"token" => token |> Base.encode64()})
      |> halt
    else
      {:user, _} ->
        conn
        |> put_status(403)
        |> json(%{})
        |> halt

      _ ->
        conn
        |> put_status(500)
        |> json(%{})
        |> halt
    end
  end

  def new(conn, _) do
    conn
    |> put_status(400)
    |> json(%{})
    |> halt
  end
end
