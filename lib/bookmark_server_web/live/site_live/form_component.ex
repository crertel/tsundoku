defmodule BookmarkServerWeb.SiteLive.FormComponent do
  use BookmarkServerWeb, :live_component

  alias BookmarkServer.Bookmarks

  @impl true
  def mount(socket) do
    available_tags = if connected?(socket), do: Bookmarks.paginate_tags().entries, else: []
    active_tags = []

    {:ok,
    socket
    |> assign(:new_tag, "")
    |> assign(:available_tags, available_tags)
    |> assign(:active_tags, active_tags)}
  end

  @impl true
  def update(%{site: site} = assigns, socket) do
    changeset = site
                |> BookmarkServer.Repo.preload(:tags)
                |> Bookmarks.change_site()

    active_tags = BookmarkServer.Repo.preload(site,:tags).tags

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:active_tags, active_tags)
     |> assign(:site, site)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"site" => site_params}, socket) do
    changeset =
      socket.assigns.site
      |> BookmarkServer.Repo.preload(:tags)
      |> Bookmarks.change_site(site_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("add_tag", _,  socket) do
    new_tag = socket.assigns.new_tag |> String.trim()
    current_user = socket.assigns.current_user
    if new_tag == "" do
      {:noreply, socket}
    else
      new_active_tags = case Bookmarks.get_tag_by_name(new_tag) do
        %Bookmarks.Tag{} = tag ->
          socket.assigns.active_tags ++ [tag] |> Enum.uniq()
        nil ->
          {:ok, tag} = Bookmarks.create_tag(%{"name" => new_tag, "created_by" => current_user})
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
    site_params_plus_tags = Map.put(site_params, "tags", socket.assigns.active_tags)
    save_site(socket, socket.assigns.action, site_params_plus_tags)
  end

  defp save_site(socket, :edit, site_params) do
    preloaded_site = BookmarkServer.Repo.preload(socket.assigns.site, :tags)
    case Bookmarks.update_site(preloaded_site, site_params) do
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
