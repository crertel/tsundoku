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
    ~H"""
    <section class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
    <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 class="text-2xl font-semibold text-slate-950">Tag</h1>
        <p class="mt-1 text-sm text-slate-700">Tag details</p>
      </div>
      <div class="flex gap-2">
        <.link patch={Routes.tag_show_path(@socket, :edit, @tag)} class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700">Edit</.link>
        <.link navigate={Routes.tag_index_path(@socket, :index)} class="rounded-md border border-slate-400 bg-slate-50 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200">Back</.link>
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

    <div class="rounded-lg border border-slate-400 bg-slate-100 p-6 shadow-sm">
      <dl class="grid gap-4 sm:grid-cols-[10rem_1fr]">
        <dt class="text-sm font-medium text-slate-700">Name</dt>
        <dd>
          <span class="inline-flex max-w-full items-center truncate rounded-full bg-slate-200 px-3 py-1 text-sm font-medium text-slate-700"><%= @tag.name %></span>
        </dd>
      </dl>
    </div>
    </section>
    """
  end
end
