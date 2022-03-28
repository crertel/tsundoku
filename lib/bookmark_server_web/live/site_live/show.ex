defmodule BookmarkServerWeb.SiteLive.Show do
  use BookmarkServerWeb, :live_view
  alias BookmarkServer.Bookmarks

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign_defaults(session, socket)}
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

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Show Site</h1>

    <%= if @live_action in [:edit] do %>
    <%= live_modal @socket, BookmarkServerWeb.SiteLive.FormComponent,
    id: @site.id,
    title: @page_title,
    action: @live_action,
    site: @site,
    current_user: @current_user,
    return_to: Routes.site_show_path(@socket, :show, @site) %>
    <% end %>

    <ul>

    <li>
    <strong>Url:</strong>
    <%= @site.url %>
    </li>

    </ul>

    <span><%= live_patch "Edit", to: Routes.site_show_path(@socket, :edit, @site), class: "button" %></span>
    <span><%= live_redirect "Back", to: Routes.site_index_path(@socket, :index) %></span>

    """
  end
end
