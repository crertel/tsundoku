defmodule TsundokuWeb.ApiController do
  use TsundokuWeb, :controller
  alias Tsundoku.Accounts
  alias Tsundoku.Bookmarks
  alias Tsundoku.Bookmarks.{Site, Tag}

  def test(conn, _) do
    json(conn, %{})
  end

  def create_user(conn, %{"email" => email, "password" => password}) do
    case Accounts.register_user(%{"email" => email, "password" => password}) do
      {:ok, _user} -> respond(conn, 201, %{})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def create_user(conn, _), do: respond(conn, 400, %{})

  def create_bookmark(conn, %{"title" => title, "url" => url, "tags" => tags} = params)
      when is_list(tags) do
    user = conn.assigns.user

    result =
      Bookmarks.create_site(%{
        "display_name" => title,
        "url" => url,
        "notes" => Map.get(params, "notes"),
        "created_by_id" => user.id,
        "tags" => resolve_tags(user, tags)
      })

    case result do
      {:ok, _site} -> respond(conn, 201, %{})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def create_bookmark(conn, _), do: respond(conn, 400, %{})

  def get_bookmark(conn, %{"bookmark_id" => bookmark_id}) do
    user = conn.assigns.user

    case get_by_uuid(&Bookmarks.get_site/1, bookmark_id) do
      nil ->
        respond(conn, 404, %{})

      %Site{created_by_id: owner_id} when owner_id != user.id ->
        respond(conn, 403, %{})

      %Site{} = bookmark ->
        bookmark = Tsundoku.Repo.preload(bookmark, :tags)

        respond(conn, 200, %{
          id: bookmark.id,
          created_by: user.id,
          display_name: bookmark.display_name,
          url: bookmark.url,
          tags: Enum.map(bookmark.tags, & &1.name)
        })
    end
  end

  def update_bookmark(
        conn,
        %{"bookmark_id" => bookmark_id, "title" => title, "url" => url, "tags" => tags} = params
      )
      when is_list(tags) do
    user = conn.assigns.user

    case get_by_uuid(&Bookmarks.get_site/1, bookmark_id) do
      nil ->
        respond(conn, 404, %{})

      %Site{created_by_id: owner_id} when owner_id != user.id ->
        respond(conn, 403, %{})

      %Site{} = bookmark ->
        result =
          Bookmarks.update_site(bookmark, %{
            "display_name" => title,
            "url" => url,
            "notes" => Map.get(params, "notes"),
            "created_by_id" => user.id,
            "tags" => resolve_tags(user, tags)
          })

        case result do
          {:ok, site} ->
            respond(conn, 201, %{
              id: site.id,
              created_by: user.id,
              title: site.display_name,
              url: site.url,
              tags: Enum.map(site.tags, & &1.name)
            })

          {:error, changeset} ->
            validation_error(conn, changeset)
        end
    end
  end

  def update_bookmark(conn, _), do: respond(conn, 400, %{})

  def create_tag(conn, %{"name" => name}) do
    user = conn.assigns.user

    case Bookmarks.create_tag(%{name: name, created_by_id: user.id}) do
      {:ok, tag} -> respond(conn, 201, %{id: tag.id, created_by: user.id, name: tag.name})
      {:error, changeset} -> validation_error(conn, changeset)
    end
  end

  def create_tag(conn, _), do: respond(conn, 400, %{})

  def get_tag(conn, %{"tag_id" => tag_id}) do
    user = conn.assigns.user

    case get_by_uuid(&Bookmarks.get_tag/1, tag_id) do
      nil ->
        respond(conn, 404, %{})

      %Tag{created_by_id: owner_id} when owner_id != user.id ->
        respond(conn, 403, %{})

      %Tag{} = tag ->
        respond(conn, 200, %{id: tag.id, created_by: user.id, name: tag.name})
    end
  end

  def update_tag(conn, %{"tag_id" => tag_id, "name" => name}) do
    user = conn.assigns.user

    case get_by_uuid(&Bookmarks.get_tag/1, tag_id) do
      nil ->
        respond(conn, 404, %{})

      %Tag{created_by_id: owner_id} when owner_id != user.id ->
        respond(conn, 403, %{})

      %Tag{} = tag ->
        case Bookmarks.update_tag(tag, %{"name" => name, "created_by_id" => user.id}) do
          {:ok, tag} -> respond(conn, 201, %{id: tag.id, created_by: user.id, name: tag.name})
          {:error, changeset} -> validation_error(conn, changeset)
        end
    end
  end

  def update_tag(conn, _), do: respond(conn, 400, %{})

  def list_tags(conn, _params) do
    user = conn.assigns.user

    tags =
      Bookmarks.list_user_tags(user.id)
      |> Enum.map(&%{id: &1.id, name: &1.name})

    json(conn, %{tags: tags})
  end

  def find_bookmark(conn, %{"url" => url}) do
    user = conn.assigns.user

    case Bookmarks.get_user_bookmark_by_url(url, user.id) do
      %Site{} = site ->
        site = Tsundoku.Repo.preload(site, :tags)

        json(conn, %{
          bookmark: %{
            id: site.id,
            url: site.url,
            display_name: site.display_name,
            notes: site.notes,
            tags: Enum.map(site.tags, & &1.name)
          }
        })

      nil ->
        conn |> put_status(404) |> json(%{}) |> halt()
    end
  end

  def find_bookmark(conn, _), do: conn |> put_status(400) |> json(%{}) |> halt()

  def random_bookmark(conn, _params) do
    user = conn.assigns.user

    case Bookmarks.random_user_site(user.id) do
      %Site{} = site ->
        json(conn, %{bookmark: %{id: site.id, url: site.url, display_name: site.display_name}})

      nil ->
        conn |> put_status(404) |> json(%{}) |> halt()
    end
  end

  def import_bookmarks(conn, %{"file" => %Plug.Upload{path: path}}) do
    user = conn.assigns.user

    try do
      {:ok, tags, urls} = Bookmarks.import_from_file(path)

      job_args = %{
        "user_id" => user.id,
        "tags" => MapSet.to_list(tags),
        "urls" =>
          Enum.map(urls, fn {bm_tags, bm_url, bm_title} ->
            %{"tags" => bm_tags, "url" => bm_url, "title" => bm_title}
          end)
      }

      {:ok, %Oban.Job{id: job_id}} =
        job_args
        |> Tsundoku.Workers.ImportBookmarks.new()
        |> Oban.insert()

      conn
      |> put_status(202)
      |> json(%{
        job_id: job_id,
        tag_count: MapSet.size(tags),
        url_count: length(urls)
      })
    rescue
      _ -> respond(conn, 422, %{msg: "Couldn't read that file as a bookmarks export."})
    end
  end

  def import_bookmarks(conn, _), do: conn |> put_status(400) |> json(%{}) |> halt()

  def import_status(conn, %{"job_id" => job_id_str}) do
    user = conn.assigns.user

    with {job_id, ""} <- Integer.parse(job_id_str),
         %Oban.Job{} = job <- Tsundoku.Repo.get(Oban.Job, job_id),
         true <- job.args["user_id"] == user.id do
      meta = job.meta || %{}

      json(conn, %{
        state: job.state,
        processed: meta["processed"] || 0,
        total: meta["total"] || 0,
        stage: meta["stage"] || "queued",
        sites_inserted: meta["sites_inserted"],
        tags_inserted: meta["tags_inserted"]
      })
    else
      _ -> conn |> put_status(404) |> json(%{msg: "not found"}) |> halt()
    end
  end

  defp respond(conn, status, body) when status >= 400,
    do: conn |> put_status(status) |> json(body) |> halt()

  defp respond(conn, status, body), do: conn |> put_status(status) |> json(body)

  # 422 with the per-field errors, plus a one-line `msg` the extension
  # shows as-is.
  defp validation_error(conn, %Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, &TsundokuWeb.CoreComponents.translate_error/1)

    msg =
      Enum.map_join(errors, "; ", fn {field, messages} ->
        "#{field}: #{Enum.join(messages, ", ")}"
      end)

    respond(conn, 422, %{msg: msg, errors: errors})
  end

  # Ids come from the URL; anything that isn't a UUID can't match a row.
  defp get_by_uuid(getter, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> getter.(uuid)
      :error -> nil
    end
  end

  # Maps tag names onto the user's tags, creating any that don't exist yet.
  defp resolve_tags(user, names) do
    names
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.map(fn name ->
      case Bookmarks.get_user_tag_by_name(name, user.id) do
        %Tag{} = tag ->
          tag

        nil ->
          {:ok, tag} = Bookmarks.create_tag(%{name: name, created_by_id: user.id})
          tag
      end
    end)
  end
end
