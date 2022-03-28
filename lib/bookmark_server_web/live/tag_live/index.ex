defmodule BookmarkServerWeb.TagLive.Index do
  use BookmarkServerWeb, :live_view

  alias BookmarkServer.Bookmarks
  alias BookmarkServer.Bookmarks.Tag

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign_defaults(session, socket)
     |> assign(
       tags: [],
       page_number: 1,
       page_size: 30,
       search: "",
       total_entries: 0,
       total_pages: 0
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Tag")
    |> assign(:tag, Bookmarks.get_tag!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Tag")
    |> assign(:tag, %Tag{})
  end

  defp apply_action(socket, :index, params) do
    assigns =
      get_and_assign_page(params["page"], params["search"] || "", socket.assigns.current_user.id)

    socket
    |> assign(assigns)
    |> assign(:page_title, "Listing Tags")
    |> assign(:tag, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    tag = Bookmarks.get_tag!(id)
    {:ok, _} = Bookmarks.delete_tag(tag)

    assigns =
      get_and_assign_page(
        socket.assigns.page_number,
        socket.assigns.search,
        socket.assigns.current_user.id
      )

    {:noreply, assign(socket, assigns)}
  end

  @impl true
  def handle_event("nav", %{"page" => page}, socket) do
    {:noreply, push_redirect(socket, to: Routes.tag_index_path(socket, :index, page: page))}
  end

  def handle_event("run_search", %{"query_field" => %{"query" => search}}, socket) do
    {:noreply,
     push_redirect(socket,
       to: Routes.tag_index_path(socket, :index, page: socket.assigns.page_number, search: search)
     )}
  end

  def get_and_assign_page(page_number, search, user_id) do
    search_string = String.trim(search)

    query_params = %{
      search_string: search_string,
      created_by: user_id
    }

    %{
      entries: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    } = Bookmarks.search_and_paginate_tags(query_params, page: page_number, page_size: 15)

    [
      tags: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages,
      search: search_string
    ]
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div>
    <div class="p-4">
    <div class="grid grid-cols-12 items-baseline border-b-2 border-black">
    <div class="col-span-2">
      <h1 class="text-lg inline-block p-1">Listing Tags</h1>
    </div>
    <div class="col-span-8">
      <div>
        <form phx-change="run_search">
          <%= text_input :query_field,
              :query,
              placeholder: "Search tags",
              autofocus: true,
              class: "w-full",
              "phx-debounce": "500" , value: @search%>
        </form>
      </div>
    </div>
    <div class="col-span-2">
      <div class="bg-blue-300 hover:text-blue-500 w-40 text-center rounded-xl m-2">
        <%= live_patch "Create New Tag", to: Routes.tag_index_path(@socket, :new) %>
      </div>
    </div>
    </div>
    </div>

    <div>
    <%= if @live_action in [:new, :edit] do %>
    <%= live_modal @socket, BookmarkServerWeb.TagLive.FormComponent,
      id: @tag.id || :new,
      title: @page_title,
      action: @live_action,
      current_user: @current_user,
      tag: @tag,
      return_to: Routes.tag_index_path(@socket, :index) %>
    <% end %>

    <div id="tags" class="p-2">
    <%= if length(@tags) > 0 do %>
      <nav class="border-t border-gray-200 m-4">
        <ul class="flex my-2">
          <li> <a class="px-2 py-2 <%= if @page_number <= 1, do: "pointer-events-none text-gray-600" %>" href="#" phx-click="nav" phx-value-page="<%= @page_number - 1 %>">Previous</a> </li>
          <%= for idx <- Enum.to_list(1..@total_pages) do %>
            <li > <a class="px-2 py-2 border-b-2 hover:border-blue-200<%= if @page_number == idx, do: "pointer-events-none text-gray-600 border-b-2 border-blue-400" %>" href="#" phx-click="nav" phx-value-page="<%= idx %>"><%= idx %></a> </li>
          <% end %>
          <li> <a class="px-2 py-2 <%= if @page_number >= @total_pages, do: "pointer-events-none text-gray-600" %>" href="#" phx-click="nav" phx-value-page="<%= @page_number + 1 %>">Next</a> </li>
        </ul>
      </nav>
      <div class="p-8 bg-white">
        <%= for tag <- @tags do %>
          <div id="tag-<%= tag.id %>" class="hover:bg-gray-200 grid grid-cols-12">
            <div class="col-span-1 flex p-2 justify-evenly items-center">
              <div class="hover:text-blue-500">
                <%= live_redirect to: Routes.tag_show_path(@socket, :show, tag) do %>
                  <%= Heroicons.Solid.information_circle(class: "h-6 w-6") %>
                <% end %>
              </div>
              <div class="hover:text-blue-500">
                <%= live_patch to: Routes.tag_index_path(@socket, :edit, tag) do %>
                  <%= Heroicons.Solid.pencil(class: "h-6 w-6") %>
                <% end %>
              </div>
              <div class="hover:text-blue-500">
                <%= link to: "#", phx_click: "delete", phx_value_id: tag.id, data: [confirm: "Are you sure?"] do %>
                  <%= Heroicons.Solid.x(class: "h-6 w-6") %>
                <% end %>
              </div>
            </div>
            <div class="col-span-11 items-center flex">
              <div>
                <%= tag.name %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% else %>
      No tags defined.
    <% end %>
    </div>
    </div>

    </div>
    """
  end
end
