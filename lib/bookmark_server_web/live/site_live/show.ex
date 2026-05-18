defmodule BookmarkServerWeb.SiteLive.Show do
  use BookmarkServerWeb, :live_view
  alias BookmarkServer.Bookmarks

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign_defaults(session, socket)}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    site =
      Bookmarks.get_site!(id)
      |> ensure_owner!(socket.assigns.current_user)
      |> BookmarkServer.Repo.preload(:tags)

    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:site, site)}
  end

  defp page_title(:show), do: "Show Site"
  defp page_title(:edit), do: "Edit Site"

  defp display_title(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp display_title(%{url: url}), do: url

  defp tag_filter_path(socket, tag) do
    Routes.site_index_path(socket, :index, q: Bookmarks.query_fragment("tag", tag.name))
  end

  defp domain_filter_path(socket, domain) do
    Routes.site_index_path(socket, :index, q: Bookmarks.query_fragment("domain", domain))
  end

  defp format_datetime(nil), do: "—"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  defp format_datetime(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-3xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 class="text-2xl font-semibold text-slate-950">Bookmark</h1>
          <p class="mt-1 text-sm text-slate-700">Details, source link, and saved metadata.</p>
        </div>
        <div class="flex shrink-0 gap-2">
          <.link
            patch={Routes.site_show_path(@socket, :edit, @site)}
            class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700"
          >
            Edit
          </.link>
          <.link
            navigate={Routes.site_index_path(@socket, :index)}
            class="rounded-md border border-slate-400 bg-slate-50 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200"
          >
            Back
          </.link>
        </div>
      </div>

      <%= if @live_action in [:edit] do %>
        <%= live_modal @socket, BookmarkServerWeb.SiteLive.FormComponent,
          id: @site.id,
          title: @page_title,
          action: @live_action,
          site: @site,
          current_user: @current_user,
          return_to: Routes.site_show_path(@socket, :show, @site) %>
      <% end %>

      <article class="overflow-hidden rounded-lg border border-slate-400 bg-slate-100 shadow-sm">
        <img
          :if={@site.og_image_url}
          src={@site.og_image_url}
          alt=""
          class="h-48 w-full bg-slate-200 object-cover sm:h-56"
          loading="lazy"
          onerror="this.style.display='none'"
        />

        <header class="border-b border-slate-300 px-6 py-5">
          <div class="flex items-start gap-3">
            <img
              :if={src = favicon_data_url(@site)}
              src={src}
              alt=""
              class="mt-1 h-5 w-5 shrink-0 rounded-sm"
              loading="lazy"
            />
            <div class="min-w-0 flex-1">
              <h2 class="break-words text-lg font-semibold text-slate-950">
                <%= display_title(@site) %>
              </h2>
              <a
                href={@site.url}
                target="_blank"
                class="mt-1 block break-all text-sm text-sky-700 hover:text-sky-900"
              >
                <%= @site.url %>
              </a>
            </div>
            <span
              :if={@site.crawl_status not in [nil, "ok"]}
              class="shrink-0 rounded-full bg-amber-100 px-2.5 py-1 text-xs font-medium text-amber-800"
              title="Latest crawl outcome"
            >
              <%= @site.crawl_status %>
            </span>
          </div>
        </header>

        <div :if={@site.description not in [nil, ""]} class="border-b border-slate-300 px-6 py-5">
          <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500">Description</h3>
          <p class="mt-2 whitespace-pre-line text-sm text-slate-800"><%= @site.description %></p>
        </div>

        <div class="border-b border-slate-300 px-6 py-5">
          <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500">Tags</h3>
          <div class="mt-2 flex flex-wrap items-center gap-2">
            <%= if @site.tags == [] do %>
              <span class="text-sm text-slate-700">No tags assigned.</span>
            <% else %>
              <%= for tag <- @site.tags do %>
                <.link
                  navigate={tag_filter_path(@socket, tag)}
                  class="rounded-full bg-slate-200 px-3 py-1 text-xs font-medium text-slate-700 hover:bg-sky-50 hover:text-sky-700"
                >
                  <%= tag.name %>
                </.link>
              <% end %>
            <% end %>
          </div>
        </div>

        <dl class="grid gap-x-4 gap-y-3 px-6 py-5 text-sm sm:grid-cols-[10rem_1fr]">
          <dt class="text-slate-500">Domain</dt>
          <dd class="min-w-0 text-slate-800">
            <.link
              :if={@site.domain}
              navigate={domain_filter_path(@socket, @site.domain)}
              class="text-sky-700 hover:text-sky-900"
            >
              <%= @site.domain %>
            </.link>
            <span :if={!@site.domain} class="text-slate-500">—</span>
          </dd>

          <dt class="text-slate-500">Added</dt>
          <dd class="text-slate-800"><%= format_datetime(@site.inserted_at) %></dd>

          <dt class="text-slate-500">Updated</dt>
          <dd class="text-slate-800"><%= format_datetime(@site.updated_at) %></dd>

          <dt class="text-slate-500">Last crawled</dt>
          <dd class="text-slate-800">
            <%= format_datetime(@site.crawled_at) %>
            <span :if={@site.crawl_status} class="ml-2 text-xs text-slate-500">
              (<%= @site.crawl_status %>)
            </span>
          </dd>
        </dl>
      </article>
    </section>
    """
  end
end
