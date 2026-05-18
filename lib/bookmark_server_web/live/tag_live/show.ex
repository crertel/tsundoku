defmodule BookmarkServerWeb.TagLive.Show do
  use BookmarkServerWeb, :live_view

  alias BookmarkServer.Bookmarks

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign_defaults(session, socket)}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    user = socket.assigns.current_user
    tag = Bookmarks.get_tag!(id) |> ensure_owner!(user)

    other_tags =
      Bookmarks.list_user_tags(user.id)
      |> Enum.reject(&(&1.id == tag.id))

    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:tag, tag)
     |> assign(:other_tags, other_tags)
     |> assign(:merge_dest, "")}
  end

  defp page_title(:show), do: "Show Tag"
  defp page_title(:edit), do: "Edit Tag"

  @impl true
  def handle_event("merge", %{"merge" => %{"dest_name" => dest_name}}, socket) do
    user = socket.assigns.current_user
    source = socket.assigns.tag
    name = String.trim(dest_name)

    case Bookmarks.get_user_tag_by_name(name, user.id) do
      nil ->
        {:noreply,
         socket
         |> assign(:merge_dest, dest_name)
         |> put_flash(:error, "No tag named #{inspect(name)} in your library.")}

      dest ->
        case Bookmarks.merge_tags(source, dest) do
          {:ok, result} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "Merged #{inspect(result.source_name)} into #{inspect(result.dest_name)} (#{result.moved} bookmark(s) moved)."
             )
             |> push_navigate(to: Routes.tag_index_path(socket, :index))}

          {:error, :same_tag} ->
            {:noreply, put_flash(socket, :error, "Can't merge a tag into itself.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-3xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 class="text-2xl font-semibold text-slate-950">Tag</h1>
          <p class="mt-1 text-sm text-slate-700">Tag details</p>
        </div>
        <div class="flex gap-2">
          <.link
            patch={Routes.tag_show_path(@socket, :edit, @tag)}
            class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700"
          >
            Edit
          </.link>
          <.link
            navigate={Routes.tag_index_path(@socket, :index)}
            class="rounded-md border border-slate-400 bg-slate-50 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200"
          >
            Back
          </.link>
        </div>
      </div>

      <%= if @live_action in [:edit] do %>
        <%= live_modal @socket, BookmarkServerWeb.TagLive.FormComponent,
          id: @tag.id,
          title: @page_title,
          action: @live_action,
          current_user: @current_user,
          tag: @tag,
          return_to: Routes.tag_show_path(@socket, :show, @tag) %>
      <% end %>

      <div class="mb-6 rounded-lg border border-slate-400 bg-slate-100 p-6 shadow-sm">
        <dl class="grid gap-4 sm:grid-cols-[10rem_1fr]">
          <dt class="text-sm font-medium text-slate-700">Name</dt>
          <dd>
            <span class="inline-flex max-w-full items-center truncate rounded-full bg-slate-200 px-3 py-1 text-sm font-medium text-slate-700">
              <%= @tag.name %>
            </span>
          </dd>
        </dl>
      </div>

      <div class="rounded-lg border border-slate-400 bg-slate-100 p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-slate-950">Merge into another tag</h2>
        <p class="mt-1 text-sm text-slate-700">
          Moves every bookmark tagged <strong><%= @tag.name %></strong>
          onto the destination tag. Bookmarks already carrying both tags just lose
          <strong><%= @tag.name %></strong>. Then <strong><%= @tag.name %></strong>
          is deleted. This cannot be undone.
        </p>

        <%= if @other_tags == [] do %>
          <p class="mt-4 text-sm text-slate-500">No other tags to merge into.</p>
        <% else %>
          <form phx-submit="merge" class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center">
            <input
              type="text"
              name="merge[dest_name]"
              value={@merge_dest}
              list="merge-dest-tags"
              placeholder="Destination tag name"
              required
              autocomplete="off"
              class="block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-sm text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200 sm:w-80"
            />
            <datalist id="merge-dest-tags">
              <%= for tag <- @other_tags do %>
                <option value={tag.name} />
              <% end %>
            </datalist>
            <button
              type="submit"
              data-confirm={"Merge \"#{@tag.name}\" into the chosen tag and then delete \"#{@tag.name}\"? This cannot be undone."}
              class="rounded-md bg-rose-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-700"
            >
              Merge
            </button>
          </form>
        <% end %>
      </div>
    </section>
    """
  end
end
