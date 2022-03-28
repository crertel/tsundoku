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
    changeset =
      site
      |> BookmarkServer.Repo.preload(:tags)
      |> Bookmarks.change_site()

    active_tags = BookmarkServer.Repo.preload(site, :tags).tags

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

  def handle_event("add_tag", _, socket) do
    new_tag = socket.assigns.new_tag |> String.trim()
    current_user = socket.assigns.current_user

    if new_tag == "" do
      {:noreply, socket}
    else
      new_active_tags =
        case Bookmarks.get_tag_by_name(new_tag) do
          %Bookmarks.Tag{} = tag ->
            (socket.assigns.active_tags ++ [tag]) |> Enum.uniq()

          nil ->
            {:ok, tag} = Bookmarks.create_tag(%{"name" => new_tag, "created_by" => current_user})
            socket.assigns.active_tags ++ [tag]
        end

      {:noreply,
       socket
       |> assign(:new_tag, "")
       |> assign(:active_tags, new_active_tags)}
    end
  end

  def handle_event("remove_tag", %{"tid" => tid}, socket) do
    new_tags =
      socket.assigns.active_tags
      |> Enum.filter(fn t -> t.id !== tid end)

    {:noreply, socket |> assign(:active_tags, new_tags)}
  end

  def handle_event("create_tag_input", %{"value" => tag_state}, socket) do
    {:noreply, socket |> assign(:new_tag, tag_state)}
  end

  def handle_event("save", %{"site" => site_params}, socket) do
    params =
      site_params
      |> Map.put("tags", socket.assigns.active_tags)
      |> Map.put("created_by_id", socket.assigns.current_user.id)

    save_site(socket, socket.assigns.action, params)
  end

  defp save_site(socket, :edit, site_params) do
    preloaded_site = BookmarkServer.Repo.preload(socket.assigns.site, :tags)
    # TODO: check that we're only updating our own sites
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
    params = site_params |> Map.put("created_by_id", socket.assigns.current_user.id)

    case Bookmarks.create_site(params) do
      {:ok, _site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Site created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
    <div class="border-black border-b-2">
    <h2 class="text-xl"><%= @title %></h2>
    </div>

    <.form let={f} for={@changeset}
    id="site-form",
    phx-target={@myself}
    phx-change="validate"
    phx-submit="save">

    <div class="m-4 grid grid-cols-6 gap-4">
    <div class="text-right">
      <%= label f, :url, class: "font-extrabold" do %> URL <% end %>
    </div>
    <div class="col-span-4">
        <%= text_input f, :url, class: "border w-full"%>
    </div>
    <div class="col-span-1 mt-4">
        <%= error_tag f, :url %>
    </div>
    </div>

    <div class="m-4 grid grid-cols-6 gap-4">
    <div class="text-right">
      <%= label f, :display_name, class: "font-extrabold" do %> Display name <% end %>
    </div>
    <div class="col-span-4">
        <%= text_input f, :display_name, class: "border w-full"%>
    </div>
    <div class="col-span-1 mt-4">
        <%= error_tag f, :display_name %>
    </div>
    </div>

    <div class="m-4 grid grid-cols-6 gap-4">
    <div class="text-right">
      <div class="font-extrabold">
        Tags
      </div>
    </div>
    <div class="col-span-5">
      <%= if length(@active_tags) > 0 do%>
        <div class="flex">
        <%= for tag <- @active_tags do %>
          <div class="m-1 p-1 px-2 bg-gray-400 rounded-full">
            <div class="inline-block px-1 cursor-pointer bg-pink-300 rounded-full text-red-700"
                 phx-value-tid={tag.id}
                 phx-click="remove_tag"
                 phx-target={@myself}>
              X
            </div>
            <%= tag.name %>
          </div>
        <% end %>
        </div>
      <% else %>
        No tags.
      <% end %>
    </div>
    </div>

    <div class="m-4 grid grid-cols-6 gap-4">
    <div class="text-right">
      <%= label f, :tag, list: "tag_list", class: "font-extrabold" do %>
        Add tag
      <% end %>
    </div>
    <div class="col-span-5 grid grid-cols-2">
      <input value={@new_tag}
             type="text"
             list="tag_list"
             phx-blur="create_tag_input"
             phx-keyup="create_tag_input"
             phx-target={@myself}
             class="border">
      <datalist id="tag_list" class="h-12 overflow-y-scroll">
        <%= for tag <- @available_tags do %>
          <option value={tag.name}/>
        <% end %>
      </datalist>
      <a href="#" class="bg-blue-300 p-2 rounded-xl" phx-click="add_tag" phx-target={@myself}> + Add Tag </a>
    </div>
    </div>
    <%= inspect @current_user %>

    <div class="grid justify-end">
    <%= submit "Save", phx_disable_with: "Saving...", class: "bg-blue-300 p-2 rounded-xl m-4"%>
    </div>
    </.form>
    </div>
    """
  end
end
