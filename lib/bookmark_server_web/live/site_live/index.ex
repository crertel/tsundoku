defmodule BookmarkServerWeb.SiteLive.Index do
  use BookmarkServerWeb, :live_view

  alias BookmarkServer.Bookmarks
  alias BookmarkServer.Bookmarks.Site

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign_defaults(session, socket)
     |> assign(
       uploaded_files: [],
       filtering_tags: [],
       available_tags: [],
       sites: [],
       page_number: 1,
       page_size: 50,
       search: "",
       tag_search: "",
       total_entries: 0,
       total_pages: 0
     )
     |> allow_upload(:bookmark_import,
       accept: ~w(.html),
       max_entries: 1,
       auto_upload: true,
       max_file_size: 32_000_000
     )}
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
    assigns =
      get_and_assign_page(
        params["page"] || 1,
        params["search"] || "",
        params["tags"] || [],
        socket.assigns.current_user.id
      )

    socket
    |> assign(:page_title, "Listing Sites")
    |> assign(:available_tags, BookmarkServer.Bookmarks.list_tags() |> Enum.map(& &1.name))
    |> assign(:site, nil)
    |> assign(assigns)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    site = Bookmarks.get_site!(id)
    {:ok, _} = Bookmarks.delete_site(site)

    assigns =
      get_and_assign_page(
        socket.assigns.page_number,
        socket.assigns.search,
        socket.assigns.filtering_tags,
        socket.assigns.current_user.id
      )

    {:noreply,
     socket
     |> assign(assigns)}
  end

  @impl true
  def handle_event("validate-upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("upload-bookmark", _params, socket) do
    socket
    |> consume_uploaded_entries(:bookmark_import, fn %{path: path}, _entry ->
      {:ok, tags, urls} = BookmarkServer.Bookmarks.import_from_file(path)
      :ok = BookmarkServer.Bookmarks.load_urls(tags, urls, socket.assigns.current_user.id)
      {:ok, :ok}
    end)

    assigns =
      get_and_assign_page(
        socket.assigns.page_number,
        socket.assigns.search,
        socket.assigns.filtering_tags,
        socket.assigns.current_user.id
      )

    {:noreply, socket |> assign(assigns)}
  end

  @impl true
  def handle_event("nav", %{"page" => page}, socket) do
    {:noreply,
     push_redirect(socket,
       to:
         Routes.site_index_path(socket, :index,
           page: page,
           search: socket.assigns.search,
           tags: socket.assigns.filtering_tags
         )
     )}
  end

  @impl true
  def handle_event("run_search", %{"query_field" => %{"query" => search}}, socket) do
    {:noreply,
     push_redirect(socket,
       to:
         Routes.site_index_path(socket, :index,
           page: socket.assigns.page_number,
           search: search,
           tags: socket.assigns.filtering_tags
         )
     )}
  end

  @impl true
  def handle_event("add_filter_tag", %{"tag" => tag}, socket) do
    tag_set = MapSet.new(socket.assigns.filtering_tags)
    new_tag_set = MapSet.put(tag_set, tag) |> MapSet.to_list()

    {:noreply,
     socket
     |> assign(page_number: 1)
     |> push_redirect(
       to:
         Routes.site_index_path(socket, :index,
           page: 1,
           search: socket.assigns.search,
           tags: new_tag_set
         )
     )}
  end

  @impl true
  def handle_event("add_filter_tag", %{"filter_tag" => %{"tag" => suggested_tag}}, socket) do
    if suggested_tag not in socket.assigns.available_tags do
      {:noreply, socket}
    else
      tag_set = MapSet.new(socket.assigns.filtering_tags)
      new_tag_set = MapSet.put(tag_set, suggested_tag) |> MapSet.to_list()

      {:noreply,
       socket
       |> assign(page_number: 1)
       |> push_redirect(
         to:
           Routes.site_index_path(socket, :index,
             page: 1,
             search: socket.assigns.search,
             tags: new_tag_set
           )
       )}
    end
  end

  @impl true
  def handle_event("remove_filter_tag", %{"tag" => tag}, socket) do
    tag_set = MapSet.new(socket.assigns.filtering_tags)
    new_tag_set = MapSet.delete(tag_set, tag) |> MapSet.to_list()

    {:noreply,
     socket
     |> assign(page_number: 1)
     |> push_redirect(
       to:
         Routes.site_index_path(socket, :index,
           page: 1,
           search: socket.assigns.search,
           tags: new_tag_set
         )
     )}
  end

  def get_and_assign_page(page_number, search, filtering_tags, user_id) do
    search_string = String.trim(search)

    query_params = %{
      search_string: search_string,
      filtering_tags: filtering_tags,
      created_by: user_id
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
      filtering_tags: filtering_tags,
      search: search_string
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-4">
    <div class="grid grid-cols-12 items-baseline border-b-2 border-black">
      <div class="col-span-2">
        <h1 class="text-lg inline-block">Listing Sites</h1>
      </div>

      <div class="col-span-8">
        <div>
          <form phx-change="run_search">
            <%= text_input :query_field,
                :query,
                placeholder: "Search bookmarked sites",
                autofocus: true,
                class: "w-full",
                "phx-debounce": "500" , value: @search%>
          </form>
        </div>
        <div>
          <small>Filtering tags (click to remove)</small>
          <div class="flex">
            <div class="m-1 rounded-full bg-green-200 p-1 px-2">
              <form phx-change="add_filter_tag">
              <%= text_input :filter_tag,
                  :tag,
                  placeholder: "Add flitering tag",
                  class: "w-full",
                  list: "tag_list",
                  "phx-debounce": "500" , value: @search%>
              <datalist id="tag_list" class="h-12 overflow-y-scroll">
                <%= for tag <- @available_tags do %>
                  <option value={tag}/>
                <% end %>
              </datalist>
            </form>
            </div>

            <%= for tag <- @filtering_tags do %>
              <div class="m-1 hover:text-blue-500 cursor-pointer rounded-full bg-blue-200 p-1 px-2"
                   phx-click="remove_filter_tag"
                   phx-value-tag={tag}>
                <%= tag %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
      <div class="col-span-2">
        <div class="bg-blue-300 hover:text-blue-500 w-40 text-center rounded-xl m-2">
          <%= live_patch "Create New Site", to: Routes.site_index_path(@socket, :new) %>
        </div>
      </div>
    </div>

    <%= if @live_action in [:new, :edit] do %>
      <%= live_modal @socket, BookmarkServerWeb.SiteLive.FormComponent,
        id: @site.id || :new,
        title: @page_title,
        action: @live_action,
        current_user: @current_user,
        site: @site,
        return_to: Routes.site_index_path(@socket, :index) %>
    <% end %>

    <div id="tags" class="p-2">
      <%= if length(@sites) > 0 do %>
      <nav class="border-t border-gray-200 m-4">
          <ul class="flex my-2">
            <li>
              <%= if @page_number <= 1 do %>
                <a class="px-2 py-2 pointer-events-none text-gray-600"
                 href="#"
                 phx-click="nav"
                 phx-value-page={@page_number - 1}>
                 Previous
                </a>
              <% else %>
              <a class="px-2 py-2"
                 href="#"
                 phx-click="nav"
                 phx-value-page={@page_number - 1}>
                 Previous
                </a>
              <% end %>

            </li>
        <%= for idx <-  Enum.to_list(1..@total_pages) do %>
            <li>
            <%= if @page_number == idx do %>
              <a class="px-2 py-2 border-b-2 hover:border-blue-200 pointer-events-none text-gray-600 border-b-2 border-blue-400" href="#" phx-click="nav" phx-value-page={idx}>
                <%= idx %>
              </a>
            <% else %>
              <a class="px-2 py-2 border-b-2 hover:border-blue-200" href="#" phx-click="nav" phx-value-page={idx}>
                <%= idx %>
              </a>
            <% end %>
            </li>
        <% end %>
            <li>
              <%= if @page_number >= @total_pages do %>
                <a class="px-2 py-2 pointer-events-none text-gray-600" href="#" phx-click="nav" phx-value-page={@page_number + 1}>
                Next
              </a>
              <% else %>
                <a class="px-2 py-2" href="#" phx-click="nav" phx-value-page={@page_number + 1}>
                  Next
                </a>
              <% end %>
            </li>
          </ul>
        </nav>
        <div class="bg-white p-8">
        <%= for site <- @sites do %>
          <div id={"site-#{site.id}"} class="bg-gray-100 hover:bg-gray-200 grid grid-cols-12">
            <div class="col-span-1 flex p-2 justify-evenly items-center">
              <div class="hover:text-blue-500">
                <%= live_redirect(to: Routes.site_show_path(@socket, :show, site)) do %>
                  <%= Heroicons.Solid.information_circle(class: "h-6 w-6") %>
                <% end %>
              </div>
              <div class="hover:text-blue-500">
                <%= live_patch to: Routes.site_index_path(@socket, :edit, site) do %>
                  <%= Heroicons.Solid.pencil(class: "h-6 w-6") %>
                <% end %>
              </div>
              <div class="hover:text-blue-500">
                <%= link to: "#", phx_click: "delete", phx_value_id: site.id, data: [confirm: "Are you sure?"] do %>
                  <%= Heroicons.Solid.x(class: "h-6 w-6") %>
                <% end %>
              </div>
            </div>
            <div class="col-span-5 items-center flex">
                <a href={ site.url } class="hover:text-blue-500" target="_blank">
                  <%= if site.display_name == "" do%>
                    <%= site.url %>
                  <% else  %>
                    <%= site.display_name %>
                  <% end %>
                </a>
            </div>
            <div class="col-span-6">
              <div class="flex items-center">
                <%= if length(site.tags) > 0 do %>
                  <%= for tag <- site.tags do %>
                    <div class="m-1 hover:text-blue-500 cursor-pointer rounded-full bg-blue-200 p-1 px-2" phx-click="add_filter_tag" phx-value-tag={tag.name}>
                      <%= tag.name %>
                    </div>
                  <% end %>
                <% else %>
                  <div class="m-1 p-1">
                  No tags assigned.
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
        </div>
      <% else %>
        No sites defined.
      <% end %>
    </div>
    <div>
      <%= for entry <- @uploads.bookmark_import.entries do %>
      <div class="w-300">
        <%= entry.client_name %> - <progress max="100" value={entry.progress} />
        </div>
      <% end %>

      <%= for {_ref, msg} <- @uploads.bookmark_import.errors do %>
        <%= msg %>
      <% end %>

      <form id="import-bookmark-form" phx-submit="upload-bookmark" phx-change="validate-upload">
        <%= live_file_input @uploads.bookmark_import %>
        <%= submit "Import" %>
      </form>
    </div>
    </div>
    """
  end
end
