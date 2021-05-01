defmodule BookmarkServerWeb.TagLive.Index do
  use BookmarkServerWeb, :live_view

  alias BookmarkServer.Bookmarks
  alias BookmarkServer.Bookmarks.Tag

  @impl true
  def mount(_params, %{"current_user" => current_user}, socket) do
    {:ok, socket
    |> assign_new( :current_user, fn -> current_user end)
    |> assign(tags: [],
      page_number: 1,
      page_size: 30,
      search: "",
      total_entries: 0,
      total_pages: 0)}
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
    assigns = get_and_assign_page(params["page"], params["search"] || "", socket.assigns.current_user.id)

    socket
    |> assign(assigns)
    |> assign(:page_title, "Listing Tags")
    |> assign(:tag, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    tag = Bookmarks.get_tag!(id)
    {:ok, _} = Bookmarks.delete_tag(tag)
    assigns = get_and_assign_page(socket.assigns.page_number,
                                  socket.assigns.search,
                                  socket.assigns.current_user.id)

    {:noreply, assign(socket, assigns)}
  end

  @impl true
  def handle_event("nav", %{"page" => page}, socket) do
    {:noreply, push_redirect(socket, to: Routes.tag_index_path(socket, :index, page: page))}
  end

  def handle_event("run_search", %{"query_field" => %{"query" => search}}, socket) do
    {:noreply, push_redirect(socket, to: Routes.tag_index_path(socket, :index, page: socket.assigns.page_number, search: search))}
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
    } =  Bookmarks.search_and_paginate_tags(query_params, page: page_number, page_size: 15)

    [
      tags: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages,
      search: search_string
    ]
  end
end
