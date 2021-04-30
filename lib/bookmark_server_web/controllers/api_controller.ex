defmodule BookmarkServerWeb.ApiController do
  use BookmarkServerWeb, :controller
  alias BookmarkServer.Accounts

  def create_user(conn, %{"email" => email, "password" => password}) do
    with {:create_user, {:ok, _user}} <- {:create_user, Accounts.register_user(%{"email" => email, "password" => password})} do
      conn
      |> send_resp(201, "{}")
    else
      {:create_user, err} ->
        conn |> send_resp(500, "{\"msg\":\"#{inspect err}\"}") |> halt
    end
  end
  def create_user(conn, _) do
    conn |> send_resp(400, "{}") |> halt
  end

  def create_site(conn, _) do
    conn |> send_resp(400, "{}") |> halt
  end

  def create_tag(conn, _) do
    conn |> send_resp(400, "{}") |> halt
  end


end
