defmodule BookmarkServerWeb.ApiController do
  use BookmarkServerWeb, :controller
  alias BookmarkServer.Accounts
  alias BookmarkServer.Bookmarks
  alias BookmarkServer.Bookmarks.{Site, Tag}

  def test(conn, _) do
    conn
    |> send_resp(200, "{}")
  end

  def create_user(conn, %{"email" => email, "password" => password}) do
    with {:create_user, {:ok, _user}} <-
           {:create_user, Accounts.register_user(%{"email" => email, "password" => password})} do
      conn
      |> send_resp(201, "{}")
    else
      {:create_user, err} ->
        conn |> send_resp(500, "{\"msg\":\"#{inspect(err)}\"}") |> halt
    end
  end

  def create_user(conn, _) do
    conn |> send_resp(400, "{}") |> halt
  end

  def create_bookmark(conn, %{"title" => title, "url" => url, "tags" => tags}) do
    user = conn.assigns.user

    saved_tags =
      Enum.reduce(tags, [], fn tag, acc ->
        try do
          {:ok, saved_tag} = Bookmarks.create_tag(%{name: tag, created_by_id: user.id})
          [saved_tag | acc]
        rescue
          _ -> acc
        end
      end)

    try do
      Bookmarks.create_site(%{
        display_name: title,
        url: url,
        created_by_id: user.id,
        tags: saved_tags
      })
    rescue
      _ -> nil
    end

    conn |> send_resp(201, "{}") |> halt
  end

  def create_bookmark(conn, _) do
    conn |> send_resp(400, "{}") |> halt
  end

  def get_bookmark(conn, %{"bookmark_id" => bookmark_id}) do
    user = conn.assigns.user

    try do
      case Bookmarks.get_site(bookmark_id) do
        %Site{} = bookmark ->
          bm =
            bookmark
            |> BookmarkServer.Repo.preload(:created_by)
            |> BookmarkServer.Repo.preload(:tags)

          if bm.created_by != user do
            conn |> send_resp(403, "{}") |> halt
          else
            {:ok, json} =
              Jason.encode(%{
                id: bm.id,
                created_by: bm.created_by.id,
                display_name: bm.display_name,
                url: bm.url,
                tags: bm.tags |> Enum.map(& &1.name)
              })

            conn |> send_resp(200, json) |> halt
          end

        nil ->
          conn |> send_resp(404, "{}") |> halt
      end
    rescue
      _ -> conn |> send_resp(404, "{}") |> halt
    end
  end

  def get_bookmark(conn, _) do
    conn |> send_resp(404, "{}") |> halt
  end

  def update_bookmark(conn, %{
        "bookmark_id" => bookmark_id,
        "title" => title,
        "url" => url,
        "tags" => tags
      }) do
    user = conn.assigns.user
    bookmark = Bookmarks.get_site(bookmark_id) |> BookmarkServer.Repo.preload(:created_by)

    cond do
      is_nil(bookmark) ->
        conn |> send_resp(404, "{}") |> halt

      bookmark.created_by != user ->
        conn |> send_resp(403, "{}") |> halt

      true ->
        new_tags =
          Enum.reduce(tags, [], fn tag, acc ->
            found_tag =
              case Bookmarks.get_tag_by_name(tag) do
                %BookmarkServer.Bookmarks.Tag{} = tag ->
                  tag

                nil ->
                  {:ok, saved_tag} = Bookmarks.create_tag(%{name: tag, created_by_id: user.id})
                  saved_tag
              end

            [found_tag | acc]
          end)

        try do
          {:ok, new_site} =
            Bookmarks.update_site(bookmark, %{
              "display_name" => title,
              "url" => url,
              "created_by_id" => user.id,
              "tags" => new_tags
            })

          {:ok, json} =
            Jason.encode(%{
              id: new_site.id,
              created_by: new_site.created_by.id,
              title: new_site.display_name,
              url: new_site.url,
              tags: Enum.map(new_site.tags, & &1.name)
            })

          conn |> send_resp(201, json) |> halt
        rescue
          err ->
            {:ok, json} = Jason.encode(%{msg: inspect(err)})
            conn |> send_resp(500, json) |> halt
        end
    end
  end

  def update_bookmark(conn, _) do
    conn |> send_resp(400, "{}") |> halt
  end

  def create_tag(conn, %{"name" => name}) do
    user = conn.assigns.user

    try do
      {:ok, %Tag{} = tag} = Bookmarks.create_tag(%{name: name, created_by_id: user.id})

      {:ok, json} =
        Jason.encode(%{
          id: tag.id,
          created_by: user.id,
          name: tag.name
        })

      conn |> send_resp(201, json) |> halt
    rescue
      err ->
        {:ok, json} = Jason.encode(%{msg: inspect(err)})
        conn |> send_resp(500, json) |> halt
    end
  end

  def create_tag(conn, _) do
    conn |> send_resp(400, "{}") |> halt
  end

  def get_tag(conn, %{"tag_id" => tag_id}) do
    user = conn.assigns.user

    try do
      case Bookmarks.get_tag(tag_id) do
        %Tag{} = tag ->
          t = tag |> BookmarkServer.Repo.preload(:created_by)

          if t.created_by != user do
            conn |> send_resp(403, "{}") |> halt
          else
            {:ok, json} =
              Jason.encode(%{
                id: t.id,
                created_by: t.created_by.id,
                name: t.name
              })

            conn |> send_resp(200, json) |> halt
          end

        nil ->
          conn |> send_resp(404, "{}") |> halt
      end
    rescue
      _ -> conn |> send_resp(404, "{}") |> halt
    end
  end

  def get_tag(conn, _) do
    conn |> send_resp(404, "{}") |> halt
  end

  def update_tag(conn, %{"tag_id" => tag_id, "name" => name}) do
    user = conn.assigns.user
    tag = Bookmarks.get_tag(tag_id) |> BookmarkServer.Repo.preload(:created_by)

    cond do
      is_nil(tag) ->
        conn |> send_resp(404, "{}") |> halt

      tag.created_by != user ->
        conn |> send_resp(403, "{}") |> halt

      true ->
        try do
          {:ok, new_tag} =
            Bookmarks.update_tag(tag, %{
              "name" => name,
              "created_by_id" => user.id
            })

          {:ok, json} =
            Jason.encode(%{
              id: new_tag.id,
              created_by: new_tag.created_by.id,
              name: new_tag.name
            })

          conn |> send_resp(201, json) |> halt
        rescue
          err ->
            {:ok, json} = Jason.encode(%{msg: inspect(err)})
            conn |> send_resp(500, json) |> halt
        end
    end
  end

  def update_tag(conn, _) do
    conn |> send_resp(400, "{}") |> halt
  end
end
