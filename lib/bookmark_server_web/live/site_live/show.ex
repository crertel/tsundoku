defmodule BookmarkServerWeb.SiteLive.Show do
  use BookmarkServerWeb, :live_view
  alias BookmarkServer.Bookmarks

  @impl true
  def mount(_params, %{"current_user" => current_user}, socket) do
    {:ok, socket
    |> assign_new( :current_user, fn -> current_user end)}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:site, Bookmarks.get_site!(id))}
  end

  defp page_title(:show), do: "Show Site"
  defp page_title(:edit), do: "Edit Site"
end
