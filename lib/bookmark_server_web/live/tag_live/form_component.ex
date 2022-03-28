defmodule BookmarkServerWeb.TagLive.FormComponent do
  use BookmarkServerWeb, :live_component

  alias BookmarkServer.Bookmarks

  @impl true
  def update(%{tag: tag} = assigns, socket) do
    changeset = Bookmarks.change_tag(tag)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"tag" => tag_params}, socket) do
    changeset =
      socket.assigns.tag
      |> Bookmarks.change_tag(tag_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"tag" => tag_params}, socket) do
    save_tag(
      socket,
      socket.assigns.action,
      tag_params |> Map.put("created_by", socket.assigns.current_user)
    )
  end

  defp save_tag(socket, :edit, tag_params) do
    # TODO: only let us update our own tags
    case Bookmarks.update_tag(socket.assigns.tag, tag_params) do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_tag(socket, :new, tag_params) do
    params = tag_params |> Map.put("created_by_id", socket.assigns.current_user.id)

    case Bookmarks.create_tag(params) do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
    <h2><%= @title %></h2>

    <.form let={f}
    for={@changeset}
    id="tag-form"
    phx-target={@myself}
    phx-change="validate"
    phx-submit="save">

    <%= label f, :name %>
    <%= text_input f, :name %>
    <%= error_tag f, :name %>

    <%= submit "Save", phx_disable_with: "Saving..." %>
    </.form>

    </div>
    """
  end
end
