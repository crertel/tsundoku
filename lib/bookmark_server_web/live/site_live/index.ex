defmodule BookmarkServerWeb.SiteLive.Index do
  use BookmarkServerWeb, :live_view

  alias BookmarkServer.Bookmarks
  alias BookmarkServer.Bookmarks.Site

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
      socket
      |> assign(
        uploaded_files: [],
        sites: [],
        page_number: 0,
        page_size: 0,
        search: "",
        total_entries: 0,
        total_pages: 0)
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

  defp apply_action(socket, :index, params) do
    assigns = get_and_assign_page( params["page"] || 1, params["search"] || "")
    socket
    |> assign(:page_title, "Listing Sites")
    |> assign( assigns)
    |> assign( :search, params["search"] || "")
    |> assign(:site, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    site = Bookmarks.get_site!(id)
    {:ok, _} = Bookmarks.delete_site(site)
    assigns = get_and_assign_page(socket.assigns.page_number, socket.assigns.search)

    {:noreply, socket
                |> assign( assigns)
    }
  end

  @impl true
  def handle_event("validate-upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("upload-bookmark", _params, socket) do
    socket
    |> consume_uploaded_entries(:bookmark_import, fn %{path: path}, _entry ->
      {:ok, tags, urls} = BookmarkServer.Bookmarks.import_from_file(path)
      :ok = BookmarkServer.Bookmarks.load_urls(tags, urls)
      :ok
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("nav", %{"page" => page}, socket) do
    {:noreply, push_redirect(socket, to: Routes.site_index_path(socket, :index, page: page, search: socket.assigns.search))}
  end

  @impl true
  def handle_event("run_search", %{"query_field" => %{"query" => search}}, socket) do
    {:noreply, push_redirect(socket, to: Routes.site_index_path(socket, :index, page: socket.assigns.page_number, search: search))}
  end

  def get_and_assign_page(page_number, search) do
    search_string = String.trim(search)

    %{
      entries: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    } = if search_string == "" do
    Bookmarks.paginate_sites(page: page_number, page_size: 50)
    else
       Bookmarks.search_and_paginate_sites(search_string, page: page_number, page_size: 50)
    end

    [
      sites: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages,
      search: search_string
    ]
  end
end
