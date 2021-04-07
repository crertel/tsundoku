defmodule BookmarkServerWeb.SiteLive.FormComponent do
  use BookmarkServerWeb, :live_component

  alias BookmarkServer.Bookmarks

  @impl true
  def mount(socket) do
    {:ok,
    socket
    |> assign(:new_tag, "")
    |> assign(:available_tags, list_tags())
    |> assign(:active_tags, [])}
  end

  @impl true
  def update(%{site: site} = assigns, socket) do
    changeset = Bookmarks.change_site(site)

    {:ok,
     socket
     |> assign(assigns)
     #|> assign(:active_tags, Ecto.Changeset.get_field(changeset, :tags)) #|> assign(:active_tags, BookmarkServer.Repo.preload(site,:tags).tags)
     |> assign(:site, site)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"site" => site_params}, socket) do
    changeset =
      socket.assigns.site
      |> Bookmarks.change_site(site_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("add_tag", _,  socket) do
    new_tag = socket.assigns.new_tag |> String.trim()
    if new_tag == "" do
      {:noreply, socket}
    else
      new_active_tags = case Bookmarks.get_tag_by_name(new_tag) do
        %Bookmarks.Tag{} = tag ->
          socket.assigns.active_tags ++ [tag] |> Enum.uniq()
        nil ->
          {:ok, tag} = Bookmarks.create_tag(%{"name" => new_tag})
          socket.assigns.active_tags ++ [tag]
      end

      {:noreply, socket
                 |> assign(:new_tag, "")
                 |> assign( :active_tags, new_active_tags)}
    end
  end

  def handle_event("remove_tag", %{"tid" => tid},  socket) do
    new_tags = socket.assigns.active_tags
              |> Enum.filter( fn t -> t.id !== tid end)
    {:noreply, socket |> assign(:active_tags, new_tags)}
  end

  def handle_event("create_tag_input", %{"value"=>tag_state},  socket) do
    {:noreply, socket |> assign(:new_tag, tag_state)}
  end

  def handle_event("save", %{"site" => site_params}, socket) do
    save_site(socket, socket.assigns.action, site_params)
  end

  defp save_site(socket, :edit, site_params) do
    case Bookmarks.update_site(socket.assigns.site, site_params) do
      {:ok, _site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Site updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_site(socket, :new, site_params) do
    case Bookmarks.create_site(site_params) do
      {:ok, _site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Site created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp list_tags() do
    Bookmarks.list_tags()
  end
end
