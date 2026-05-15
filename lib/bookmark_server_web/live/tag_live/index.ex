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
    tag = Bookmarks.get_tag!(id) |> ensure_owner!(socket.assigns.current_user)

    socket
    |> assign(:page_title, "Edit Tag")
    |> assign(:tag, tag)
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
    tag = Bookmarks.get_tag!(id) |> ensure_owner!(socket.assigns.current_user)
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
    {:noreply, push_patch(socket, to: Routes.tag_index_path(socket, :index, page: page))}
  end

  def handle_event("run_search", %{"query_field" => %{"query" => search}}, socket) do
    {:noreply,
     push_patch(socket,
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
    ~H"""
    <section class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-6 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 class="text-2xl font-semibold text-slate-950">Tags</h1>
          <p class="mt-1 text-sm text-slate-700"><%= @total_entries %> saved tags</p>
        </div>

        <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
          <form phx-change="run_search" class="w-full sm:w-80">
            <%= text_input :query_field,
                :query,
                placeholder: "Search tags",
                autofocus: true,
                class: "block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-sm text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200",
                "phx-debounce": "500" , value: @search%>
          </form>

          <.link patch={Routes.tag_index_path(@socket, :new)} class="inline-flex items-center justify-center rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700">
            New Tag
          </.link>
        </div>
      </div>

    <%= if @live_action in [:new, :edit] do %>
      <%= live_modal @socket, BookmarkServerWeb.TagLive.FormComponent,
        id: @tag.id || :new,
        title: @page_title,
        action: @live_action,
        current_user: @current_user,
        tag: @tag,
        return_to: Routes.tag_index_path(@socket, :index) %>
    <% end %>

      <div id="tags" class="overflow-hidden rounded-lg border border-slate-400 bg-slate-100 shadow-sm">
      <%= if length(@tags) > 0 do %>
        <div class="divide-y divide-slate-300">
          <%= for tag <- @tags do %>
            <div id={"tag-#{tag.id}"} class="grid gap-3 px-4 py-3 transition hover:bg-slate-200 sm:grid-cols-[7rem_1fr] sm:items-center">
              <div class="flex items-center gap-2 text-slate-700">
                <.link navigate={Routes.tag_show_path(@socket, :show, tag)} class="rounded-md p-1 hover:bg-slate-200 hover:text-sky-700" title="View">
                  <Heroicons.information_circle class="h-5 w-5" />
                </.link>
                <.link patch={Routes.tag_index_path(@socket, :edit, tag)} class="rounded-md p-1 hover:bg-slate-200 hover:text-sky-700" title="Edit">
                  <Heroicons.pencil class="h-5 w-5" />
                </.link>
                <%= link to: "#", phx_click: "delete", phx_value_id: tag.id, data: [confirm: "Are you sure?"], class: "rounded-md p-1 hover:bg-red-50 hover:text-red-700", title: "Delete" do %>
                  <Heroicons.x_mark class="h-5 w-5" />
                <% end %>
              </div>
              <div class="min-w-0">
                <span class="inline-flex max-w-full items-center truncate rounded-full bg-slate-200 px-3 py-1 text-sm font-medium text-slate-700"><%= tag.name %></span>
              </div>
            </div>
          <% end %>
        </div>

        <nav class="border-t border-slate-300 px-4 py-3">
          <ul class="flex flex-wrap items-center gap-1 text-sm">
            <li>
              <a class={["rounded-md px-3 py-2 font-medium text-slate-800 hover:bg-slate-200 hover:text-slate-950", @page_number <= 1 && "pointer-events-none text-slate-400 hover:bg-transparent"]} href="#" phx-click="nav" phx-value-page={@page_number - 1}>Previous</a>
            </li>
          <%= for idx <- Enum.to_list(1..@total_pages) do %>
            <li>
              <a class={["rounded-md px-3 py-2 font-medium text-slate-800 hover:bg-slate-200 hover:text-slate-950", @page_number == idx && "pointer-events-none bg-sky-50 text-sky-700"]} href="#" phx-click="nav" phx-value-page={idx}><%= idx %></a>
            </li>
          <% end %>
            <li>
              <a class={["rounded-md px-3 py-2 font-medium text-slate-800 hover:bg-slate-200 hover:text-slate-950", @page_number >= @total_pages && "pointer-events-none text-slate-400 hover:bg-transparent"]} href="#" phx-click="nav" phx-value-page={@page_number + 1}>Next</a>
            </li>
          </ul>
        </nav>
      <% else %>
        <div class="px-6 py-12 text-center text-sm text-slate-700">No tags defined.</div>
      <% end %>
      </div>
    </section>
    """
  end
end
