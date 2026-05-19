defmodule BookmarkServerWeb.SavedSearchLive.Index do
  use BookmarkServerWeb, :live_view

  alias BookmarkServer.Bookmarks
  alias BookmarkServer.Bookmarks.SavedSearch

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign_defaults(session, socket) |> assign(page_title: "Saved searches")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:searches, Bookmarks.list_user_saved_searches(user.id))
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:changeset, nil)
    |> assign(:editing, nil)
  end

  defp apply_action(socket, :new, params) do
    case String.trim(Map.get(params, "query", "")) do
      "" ->
        socket
        |> put_flash(
          :info,
          "Build a query in the sites search bar, then click \"Save\" to name it."
        )
        |> push_navigate(to: ~p"/sites")

      query ->
        prefill = %SavedSearch{query: query}

        socket
        |> assign(:changeset, Bookmarks.change_saved_search(prefill))
        |> assign(:editing, :new)
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user = socket.assigns.current_user
    ss = Bookmarks.get_saved_search!(id) |> ensure_owner!(user)
    socket |> assign(:changeset, Bookmarks.change_saved_search(ss)) |> assign(:editing, ss)
  end

  @impl true
  def handle_event("save", %{"saved_search" => attrs}, socket) do
    user = socket.assigns.current_user
    attrs = Map.put(attrs, "created_by_id", user.id)

    result =
      case socket.assigns.editing do
        :new -> Bookmarks.create_saved_search(attrs)
        %SavedSearch{} = ss -> Bookmarks.update_saved_search(ss, attrs)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved search saved.")
         |> push_patch(to: ~p"/searches")}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    ss = Bookmarks.get_saved_search!(id) |> ensure_owner!(user)
    {:ok, _} = Bookmarks.delete_saved_search(ss)

    {:noreply,
     socket
     |> put_flash(:info, "Deleted.")
     |> assign(:searches, Bookmarks.list_user_saved_searches(user.id))}
  end

  @impl true
  def handle_event("enable_feed", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    ss = Bookmarks.get_saved_search!(id) |> ensure_owner!(user)
    {:ok, _} = Bookmarks.enable_feed(ss)

    {:noreply,
     socket
     |> put_flash(:info, "Feed enabled.")
     |> assign(:searches, Bookmarks.list_user_saved_searches(user.id))}
  end

  @impl true
  def handle_event("disable_feed", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    ss = Bookmarks.get_saved_search!(id) |> ensure_owner!(user)
    {:ok, _} = Bookmarks.disable_feed(ss)

    {:noreply,
     socket
     |> put_flash(:info, "Feed revoked.")
     |> assign(:searches, Bookmarks.list_user_saved_searches(user.id))}
  end

  @impl true
  def handle_event("rotate_feed", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    ss = Bookmarks.get_saved_search!(id) |> ensure_owner!(user)
    {:ok, _} = Bookmarks.enable_feed(ss)

    {:noreply,
     socket
     |> put_flash(:info, "Feed token rotated. The old URL no longer works.")
     |> assign(:searches, Bookmarks.list_user_saved_searches(user.id))}
  end

  defp feed_url(token), do: "/feeds/#{token}.atom"

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-6">
        <h1 class="text-2xl font-semibold text-slate-950">Saved searches</h1>
        <p class="mt-1 text-sm text-slate-700">
          Name a query, optionally publish it as an Atom feed. To
          create one, build a query on the
          <.link navigate={~p"/sites"} class="text-sky-700 hover:text-sky-900">sites page</.link>
          and click <strong>Save</strong>.
        </p>
      </div>

      <div :if={@editing} class="mb-8 rounded-lg border border-slate-400 bg-slate-100 p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-slate-950">
          <%= if @editing == :new, do: "Name this search", else: "Edit saved search" %>
        </h2>

        <.form :let={f} for={@changeset} phx-submit="save" class="mt-4 space-y-4">
          <div>
            <%= label f, :name, class: "block text-sm font-medium text-slate-700" %>
            <%= text_input f, :name,
              required: true,
              autofocus: true,
              class:
                "mt-1 block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200" %>
            <%= error_tag f, :name %>
          </div>

          <div>
            <span class="block text-sm font-medium text-slate-700">Query</span>
            <p class="mt-1 break-all rounded-md border border-slate-300 bg-slate-200 px-3 py-2 font-mono text-sm text-slate-800">
              <%= Ecto.Changeset.get_field(@changeset, :query) || "" %>
            </p>
            <%= hidden_input f, :query %>
            <p class="mt-1 text-xs text-slate-500">
              To change the query, rerun the search on the sites page and save again.
            </p>
          </div>

          <div class="flex gap-2">
            <%= submit "Save",
              class:
                "rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700" %>
            <.link
              patch={~p"/searches"}
              class="rounded-md border border-slate-400 bg-slate-50 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>

      <%= if @searches == [] do %>
        <p class="rounded-lg border border-slate-300 bg-white p-6 text-sm text-slate-700">
          No saved searches yet.
          <.link patch={~p"/searches/new"} class="text-sky-700 hover:text-sky-900">Create one</.link>.
        </p>
      <% else %>
        <ul class="space-y-3">
          <%= for ss <- @searches do %>
            <li class="rounded-lg border border-slate-400 bg-slate-100 p-4 shadow-sm">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="min-w-0 flex-1">
                  <div class="flex items-center gap-2">
                    <h3 class="text-base font-semibold text-slate-950"><%= ss.name %></h3>
                    <span
                      :if={ss.feed_token}
                      class="rounded-full bg-emerald-100 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-emerald-800"
                    >
                      Feed live
                    </span>
                  </div>
                  <p class="mt-1 font-mono text-xs text-slate-600 break-all">
                    <%= if ss.query == "", do: "(empty query — all sites)", else: ss.query %>
                  </p>
                  <p :if={ss.feed_token} class="mt-2 text-xs text-slate-700">
                    Feed:
                    <a
                      href={feed_url(ss.feed_token)}
                      class="font-mono text-sky-700 hover:text-sky-900"
                      target="_blank"
                      rel="noopener"
                    >
                      <%= feed_url(ss.feed_token) %>
                    </a>
                  </p>
                </div>
                <div class="flex shrink-0 flex-wrap items-center gap-2">
                  <.link
                    navigate={~p"/sites?q=#{ss.query}"}
                    class="rounded-md border border-slate-400 bg-slate-50 px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-sm hover:bg-slate-200"
                  >
                    Run
                  </.link>
                  <.link
                    patch={~p"/searches/#{ss.id}/edit"}
                    class="rounded-md border border-slate-400 bg-slate-50 px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-sm hover:bg-slate-200"
                  >
                    Edit
                  </.link>
                  <%= if ss.feed_token do %>
                    <button
                      phx-click="rotate_feed"
                      phx-value-id={ss.id}
                      data-confirm="Rotate the feed token? Subscribers using the old URL will stop receiving updates."
                      class="rounded-md border border-slate-400 bg-slate-50 px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-sm hover:bg-slate-200"
                    >
                      Rotate
                    </button>
                    <button
                      phx-click="disable_feed"
                      phx-value-id={ss.id}
                      data-confirm="Revoke this feed? The URL will stop working."
                      class="rounded-md bg-amber-500 px-3 py-1.5 text-xs font-semibold text-white shadow-sm hover:bg-amber-600"
                    >
                      Revoke feed
                    </button>
                  <% else %>
                    <button
                      phx-click="enable_feed"
                      phx-value-id={ss.id}
                      class="rounded-md bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white shadow-sm hover:bg-emerald-700"
                    >
                      Publish feed
                    </button>
                  <% end %>
                  <button
                    phx-click="delete"
                    phx-value-id={ss.id}
                    data-confirm={"Delete saved search \"#{ss.name}\"?"}
                    class="rounded-md bg-rose-600 px-3 py-1.5 text-xs font-semibold text-white shadow-sm hover:bg-rose-700"
                  >
                    Delete
                  </button>
                </div>
              </div>
            </li>
          <% end %>
        </ul>
      <% end %>
    </section>
    """
  end
end
