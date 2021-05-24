defmodule BookmarkServerWeb.ApiController do
  use BookmarkServerWeb, :controller
  alias BookmarkServer.Accounts
  alias BookmarkServer.Bookmarks

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

  def create_bookmark(conn, %{"title" => title, "url" => url, "tags" => tags}) do
    user = conn.assigns.user

    saved_tags = Enum.reduce( tags, [], fn(tag,acc) ->
      try do
        {:ok, saved_tag}  = Bookmarks.create_tag(%{name: tag, created_by_id: user.id})
        [saved_tag | acc ]
      rescue
        _ -> acc
      end
    end)


    try do
      Bookmarks.create_site(%{display_name: title, url: url, created_by_id: user.id, tags: saved_tags})
    rescue
      _ -> nil
    end

    conn |> send_resp(201, "{}") |> halt
  end
  def create_bookmark(conn, _) do
    conn |> send_resp(400, "{}") |> halt
  end

  def update_bookmark(conn, %{"title" => title, "url" => url, "tags" => tags}) do
    user = conn.assigns.user
    saved_tags = Enum.reduce( tags, [], fn(tag,acc) ->
      try do
        {:ok, saved_tag}  = Bookmarks.create_tag(%{name: tag, created_by_id: user.id})
        [saved_tag | acc ]
      rescue
        _ -> acc
      end
    end)

    try do
      Bookmarks.create_site(%{display_name: title, url: url, created_by_id: user.id, tags: saved_tags})
    rescue
      _ -> nil
    end

    conn |> send_resp(201, "{}") |> halt
  end
  def update_bookmark(conn, _) do
    conn |> send_resp(400, "{}") |> halt
  end

  def create_tag(conn, %{"name" => name}) do
    user = conn.assigns.user

    try do
      Bookmarks.create_tag(%{name: name, created_by_id: user.id})
    rescue
      _ -> nil
    end

    conn |> send_resp(201, "{}") |> halt
  end
  def create_tag(conn, _) do
    conn |> send_resp(400, "{}") |> halt
  end
end
