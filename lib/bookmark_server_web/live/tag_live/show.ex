defmodule BookmarkServerWeb.TagLive.Show do
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
     |> assign(:tag, Bookmarks.get_tag!(id))}
  end

  defp page_title(:show), do: "Show Tag"
  defp page_title(:edit), do: "Edit Tag"

  @impl true
  def render(assigns) do
    ~L"""
    <div>
    <h1>Show Tag</h1>

    <%= if @live_action in [:edit] do %>
      <%= live_modal @socket, BookmarkServerWeb.TagLive.FormComponent,
        id: @tag.id,
        title: @page_title,
        action: @live_action,
        current_user: @current_user,
        tag: @tag,
        return_to: Routes.tag_show_path(@socket, :show, @tag) %>
    <% end %>

    <ul>

      <li>
        <strong>Name:</strong>
        <%= @tag.name %>
      </li>

    </ul>

    <span><%= live_patch "Edit", to: Routes.tag_show_path(@socket, :edit, @tag), class: "button" %></span>
    <span><%= live_redirect "Back", to: Routes.tag_index_path(@socket, :index) %></span>
    </div>
    """
  end
end
