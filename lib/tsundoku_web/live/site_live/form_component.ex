defmodule TsundokuWeb.SiteLive.FormComponent do
  use TsundokuWeb, :live_component

  alias Tsundoku.Bookmarks

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:new_tag, "")
     |> assign(:available_tags, [])
     |> assign(:active_tags, [])}
  end

  @impl true
  def update(%{site: site} = assigns, socket) do
    changeset =
      site
      |> Tsundoku.Repo.preload(:tags)
      |> Bookmarks.change_site()

    active_tags = Tsundoku.Repo.preload(site, :tags).tags
    available_tags = Bookmarks.list_user_tags(assigns.current_user.id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:available_tags, available_tags)
     |> assign(:active_tags, active_tags)
     |> assign(:site, site)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"site" => site_params}, socket) do
    changeset =
      socket.assigns.site
      |> Tsundoku.Repo.preload(:tags)
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
        case Bookmarks.get_user_tag_by_name(new_tag, current_user.id) do
          %Bookmarks.Tag{} = tag ->
            (socket.assigns.active_tags ++ [tag]) |> Enum.uniq()

          nil ->
            {:ok, tag} =
              Bookmarks.create_tag(%{"name" => new_tag, "created_by_id" => current_user.id})

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
    preloaded_site = Tsundoku.Repo.preload(socket.assigns.site, :tags)
    # TODO: check that we're only updating our own sites
    case Bookmarks.update_site(preloaded_site, site_params) do
      {:ok, _site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Site updated successfully")
         |> push_navigate(to: socket.assigns.return_to)}

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
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :tag_list_id, "site-form-tag-list-#{assigns.id}")

    ~H"""
    <div class="pr-8">
    <div class="border-b border-slate-300 pb-4">
    <h2 class="text-xl font-semibold text-slate-950"><%= @title %></h2>
    </div>

    <.form :let={f} for={@changeset}
    id="site-form"
    phx-target={@myself}
    phx-change="validate"
    phx-submit="save"
    class="mt-6 space-y-5">

    <div>
      <%= label f, :url, class: "block text-sm font-medium text-slate-700" do %> URL <% end %>
        <%= text_input f, :url, class: "mt-2 block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"%>
        <%= error_tag f, :url %>
    </div>

    <div>
      <%= label f, :display_name, class: "block text-sm font-medium text-slate-700" do %> Display name <% end %>
        <%= text_input f, :display_name, class: "mt-2 block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"%>
        <%= error_tag f, :display_name %>
    </div>

    <div>
      <%= label f, :notes, class: "block text-sm font-medium text-slate-700" do %> Notes <% end %>
      <p class="mt-1 text-xs text-slate-500">
        Your own commentary. The auto-fetched description from the page
        is shown separately.
      </p>
        <%= textarea f, :notes, rows: 4, class: "mt-2 block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"%>
        <%= error_tag f, :notes %>
    </div>

    <div>
      <div class="text-sm font-medium text-slate-700">
        Tags
      </div>
    <div class="mt-2">
      <%= if length(@active_tags) > 0 do%>
        <div class="flex flex-wrap gap-2">
        <%= for tag <- @active_tags do %>
          <div class="inline-flex items-center gap-2 rounded-full bg-slate-200 px-3 py-1 text-sm font-medium text-slate-700">
            <button type="button" class="rounded-full text-red-600 hover:text-red-800"
                 phx-value-tid={tag.id}
                 phx-click="remove_tag"
                 phx-target={@myself}>
              x
            </button>
            <%= tag.name %>
          </div>
        <% end %>
        </div>
      <% else %>
        <span class="text-sm text-slate-700">No tags.</span>
      <% end %>
    </div>
    </div>

    <div>
      <%= label f, :tag, list: @tag_list_id, class: "block text-sm font-medium text-slate-700" do %>
        Add tag
      <% end %>
    <div class="mt-2 flex flex-col gap-3 sm:flex-row">
      <input value={@new_tag}
             type="text"
             list={@tag_list_id}
             phx-blur="create_tag_input"
             phx-keyup="create_tag_input"
             phx-target={@myself}
             class="block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200">
      <datalist id={@tag_list_id} class="h-12 overflow-y-scroll">
        <%= for tag <- @available_tags do %>
          <option value={tag.name}/>
        <% end %>
      </datalist>
      <a href="#" class="inline-flex items-center justify-center rounded-md border border-slate-400 bg-slate-50 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200" phx-click="add_tag" phx-target={@myself}>Add tag</a>
    </div>
    </div>

    <div class="flex justify-end border-t border-slate-300 pt-5">
    <%= submit "Save", phx_disable_with: "Saving...", class: "rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700"%>
    </div>
    </.form>
    </div>
    """
  end
end
