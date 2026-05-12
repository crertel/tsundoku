defmodule BookmarkServerWeb.DomainLive.Index do
  use BookmarkServerWeb, :live_view

  alias BookmarkServer.Bookmarks

  @impl true
  def mount(_params, session, socket) do
    socket = assign_defaults(session, socket)

    {:ok,
     socket
     |> assign(:page_title, "Domains")
     |> assign(:domains, Bookmarks.list_domains(socket.assigns.current_user.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-6">
        <h1 class="text-2xl font-semibold text-slate-950">Domains</h1>
        <p class="mt-1 text-sm text-slate-700"><%= length(@domains) %> bookmark domains</p>
      </div>

      <div class="overflow-hidden rounded-lg border border-slate-400 bg-slate-100 shadow-sm">
        <%= if @domains == [] do %>
          <div class="px-6 py-12 text-center text-sm text-slate-700">No bookmark domains found.</div>
        <% else %>
          <div class="divide-y divide-slate-300">
            <%= for domain <- @domains do %>
              <div id={"domain-#{domain.domain}"} class="px-4 py-4 transition hover:bg-slate-200">
                <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                  <div class="min-w-0">
                    <div class="truncate text-sm font-semibold text-slate-950"><%= domain.domain %></div>
                    <div class="mt-1 text-xs text-slate-700">
                      <%= domain.count %> <%= if domain.count == 1, do: "bookmark", else: "bookmarks" %>
                    </div>
                  </div>
                  <.link navigate={Routes.site_index_path(@socket, :index, q: Bookmarks.query_fragment("domain", domain.domain))} class="rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200">
                    View sites
                  </.link>
                </div>

                <div class="mt-3 flex flex-wrap items-center gap-2">
                  <%= if domain.tags == [] do %>
                    <span class="text-sm text-slate-700">No tags assigned.</span>
                  <% else %>
                    <%= for tag <- domain.tags do %>
                      <.link navigate={Routes.site_index_path(@socket, :index, q: Bookmarks.query_fragment("tag", tag.name))} class="rounded-full bg-slate-200 px-3 py-1 text-xs font-medium text-slate-700 hover:bg-sky-50 hover:text-sky-700">
                        <%= tag.name %> <span class="text-slate-500"><%= tag.count %></span>
                      </.link>
                    <% end %>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </section>
    """
  end
end
