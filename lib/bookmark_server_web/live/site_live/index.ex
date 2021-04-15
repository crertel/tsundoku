defmodule BookmarkServerWeb.SiteLive.Index do
  use BookmarkServerWeb, :live_view

  alias BookmarkServer.Bookmarks
  alias BookmarkServer.Bookmarks.Site

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
    socket
    |> assign(:sites, list_sites())
    |> assign(:uploaded_files,[])
    |> allow_upload(:bookmark_import, accept: ~w(.html), max_entries: 1, auto_upload: true, max_file_size: 32_000_000)
    }
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Site")
    |> assign(:site, Bookmarks.get_site!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Site")
    |> assign(:site, %Site{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Sites")
    |> assign(:site, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    site = Bookmarks.get_site!(id)
    {:ok, _} = Bookmarks.delete_site(site)

    {:noreply, assign(socket, :sites, list_sites())}
  end

  @impl true
  def handle_event("validate-upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("upload-bookmark", _params, socket) do
    socket
    |> consume_uploaded_entries(:bookmark_import, fn %{path: path}, _entry ->
      {:ok, tags, urls} = BookmarkServer.Bookmarks.import_from_file(path)
      :ok = BookmarkServer.Bookmarks.load_urls(tags, urls)
      Enum.map(urls, fn {"a", bm_tags, [bm_title]} ->
        {"href", bm_url} = List.keyfind(bm_tags, "href", 0)
        %{
          url: bm_url,
          display_name: bm_title,
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now(),
        }
      end)
      |> Enum.chunk_every(200)
      |> Enum.each( fn(chunk) ->
        Ecto.Multi.new()
        |> Ecto.Multi.insert_all(:insert_all,
            BookmarkServer.Bookmarks.Site,
            chunk,
            on_conflict: :nothing
            #conflict_target: [:url]
        )
        |> BookmarkServer.Repo.transaction()
      end)
      :ok
    end)

    {:noreply, socket}
  end

  defp list_sites do
    Bookmarks.list_sites()
    |> BookmarkServer.Repo.preload(:tags)
  end
end
