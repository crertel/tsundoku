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
        filtering_tags: [],
        available_tags: [],
        sites: [],
        page_number: 0,
        page_size: 0,
        search: "",
        tag_search: "",
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
    assigns = get_and_assign_page( params["page"] || 1, params["search"] || "", params["tags"] || [])
    socket
    |> assign(:page_title, "Listing Sites")
    |> assign( assigns)
    |> assign( :search, params["search"] || "")
    |> assign( :available_tags, BookmarkServer.Bookmarks.list_tags() |> Enum.map(&(&1.name)))
    |> assign( :filtering_tags, params["tags"] || [])
    |> assign(:site, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    site = Bookmarks.get_site!(id)
    {:ok, _} = Bookmarks.delete_site(site)
    assigns = get_and_assign_page(socket.assigns.page_number, socket.assigns.search, socket.assigns.filtering_tags)

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
    {:noreply, push_redirect(socket, to: Routes.site_index_path(socket, :index, page: page, search: socket.assigns.search, tags: socket.assigns.filtering_tags))}
  end

  @impl true
  def handle_event("run_search", %{"query_field" => %{"query" => search}}, socket) do
    {:noreply, push_redirect(socket, to: Routes.site_index_path(socket, :index, page: socket.assigns.page_number, search: search, tags: socket.assigns.filtering_tags))}
  end

  @impl true
  def handle_event("add_filter_tag", %{"tag"=> tag}, socket) do
    tag_set = MapSet.new(socket.assigns.filtering_tags)
    new_tag_set = MapSet.put(tag_set, tag) |> MapSet.to_list()
    {:noreply, socket
      |> assign(page_number: 1)
      |> push_redirect(to: Routes.site_index_path(socket, :index, page: 1, search: socket.assigns.search, tags: new_tag_set))}
  end

  @impl true
  def handle_event("add_filter_tag", %{"filter_tag" => %{"tag"=>suggested_tag}}, socket) do
    if not (suggested_tag in socket.assigns.available_tags) do
      {:noreply, socket}
    else
      tag_set = MapSet.new(socket.assigns.filtering_tags)
      new_tag_set = MapSet.put(tag_set, suggested_tag) |> MapSet.to_list()
      {:noreply, socket
        |> assign(page_number: 1)
        |> push_redirect(to: Routes.site_index_path(socket, :index, page: 1, search: socket.assigns.search, tags: new_tag_set))}
    end
  end

  @impl true
  def handle_event("remove_filter_tag", %{"tag"=> tag}, socket) do
    tag_set = MapSet.new(socket.assigns.filtering_tags)
    new_tag_set = MapSet.delete(tag_set, tag) |> MapSet.to_list()
    {:noreply, socket
    |> assign(page_number: 1)
    |> push_redirect(to: Routes.site_index_path(socket, :index, page: 1, search: socket.assigns.search, tags: new_tag_set))}
  end

  def get_and_assign_page(page_number, search, filtering_tags) do
    search_string = String.trim(search)

    query_params = %{
      search_string: search_string,
      filtering_tags: filtering_tags
    }

    %{
      entries: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    } = Bookmarks.search_and_paginate_sites(query_params, page: page_number, page_size: 50)

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
