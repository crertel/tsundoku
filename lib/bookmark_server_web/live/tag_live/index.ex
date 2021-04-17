defmodule BookmarkServerWeb.TagLive.Index do
  use BookmarkServerWeb, :live_view

  alias BookmarkServer.Bookmarks
  alias BookmarkServer.Bookmarks.Tag

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, tags: [],
    page_number: 0,
    page_size: 0,
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
    assigns = get_and_assign_page(params["page"], params["search"] || "")
    socket
    |> assign(assigns)
    |> assign(:page_title, "Listing Tags")
    |> assign(:tag, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    tag = Bookmarks.get_tag!(id)
    {:ok, _} = Bookmarks.delete_tag(tag)
    assigns = get_and_assign_page(socket.assigns.page_number, socket.assigns.search)

    {:noreply, assign(socket, assigns)}
  end

  @impl true
  def handle_event("nav", %{"page" => page}, socket) do
    {:noreply, push_redirect(socket, to: Routes.tag_index_path(socket, :index, page: page))}
  end

  def handle_event("run_search", %{"query_field" => %{"query" => search}}, socket) do
    {:noreply, push_redirect(socket, to: Routes.tag_index_path(socket, :index, page: socket.assigns.page_number, search: search))}
  end

  def get_and_assign_page(page_number, search) do
    clean_search = String.trim(search)
    %{
      entries: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    } = if clean_search == "" do
      Bookmarks.paginate_tags(page: page_number, page_size: 5)
    else
      Bookmarks.search_and_paginate_tags(clean_search, page: page_number, page_size: 5)
    end

    [
      tags: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages,
      search: clean_search
    ]
  end
end
