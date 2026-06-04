defmodule TsundokuWeb.DomainLive.Index do
  use TsundokuWeb, :live_view

  alias Tsundoku.Bookmarks

  @page_size 50

  @impl true
  def mount(_params, session, socket) do
    socket = assign_defaults(session, socket)

    {:ok,
     socket
     |> subscribe_to_bookmarks(socket.assigns.current_user.id)
     |> assign(:page_title, "Domains")
     |> assign(:page_size, @page_size)
     |> assign(:domains, [])
     |> assign(:search, "")
     |> assign(:sort, :count)
     |> assign(:page_number, 1)
     |> assign(:total_entries, 0)
     |> assign(:total_pages, 0)}
  end

  @impl true
  def handle_info({:bookmarks_event, _kind, _payload}, socket) do
    {:noreply, schedule_bookmarks_refetch(socket)}
  end

  def handle_info(:bookmarks_refetch, socket) do
    # Filter-blind: re-run the current page query.
    page_result =
      Bookmarks.list_domains(socket.assigns.current_user.id,
        page: socket.assigns.page_number,
        page_size: socket.assigns.page_size,
        search: socket.assigns.search,
        sort: socket.assigns.sort
      )

    {:noreply,
     socket
     |> assign(:domains, page_result.entries)
     |> assign(:total_entries, page_result.total_entries)
     |> assign(:total_pages, page_result.total_pages)
     |> assign(:bookmarks_refetch_timer, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = params["search"] || ""
    page = parse_int(params["page"], 1)
    sort = parse_sort(params["sort"])

    page_result =
      Bookmarks.list_domains(socket.assigns.current_user.id,
        page: page,
        page_size: @page_size,
        search: search,
        sort: sort
      )

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:sort, sort)
     |> assign(:domains, page_result.entries)
     |> assign(:page_number, page_result.page_number)
     |> assign(:page_size, page_result.page_size)
     |> assign(:total_entries, page_result.total_entries)
     |> assign(:total_pages, page_result.total_pages)}
  end

  @impl true
  def handle_event("run_search", %{"query_field" => %{"query" => query}}, socket) do
    {:noreply, push_patch(socket, to: index_path(socket, page: 1, search: String.trim(query)))}
  end

  @impl true
  def handle_event("nav", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: index_path(socket, page: page))}
  end

  @impl true
  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply, push_patch(socket, to: index_path(socket, page: 1, sort: sort))}
  end

  defp parse_int(nil, fallback), do: fallback

  defp parse_int(value, fallback) do
    case Integer.parse(to_string(value)) do
      {n, _} when n >= 1 -> n
      _ -> fallback
    end
  end

  defp parse_sort("alpha"), do: :alpha
  defp parse_sort(_), do: :count

  defp index_path(socket, overrides) do
    sort =
      case Keyword.get(overrides, :sort, socket.assigns[:sort]) do
        :alpha -> "alpha"
        "alpha" -> "alpha"
        _ -> nil
      end

    base = [
      page: Keyword.get(overrides, :page, 1),
      search: Keyword.get(overrides, :search, socket.assigns[:search] || "")
    ]

    full = if sort, do: base ++ [sort: sort], else: base
    Routes.domain_index_path(socket, :index, full)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-6">
        <h1 class="text-2xl font-semibold text-slate-950">Domains</h1>
        <p class="mt-1 text-sm text-slate-700"><%= @total_entries %> bookmark domains</p>
      </div>

      <div class="mb-4 flex items-center justify-end gap-2 text-xs text-slate-600">
        <span>Sort:</span>
        <button
          type="button"
          phx-click="set_sort"
          phx-value-sort="count"
          class={[
            "rounded-md px-2 py-1 font-medium",
            @sort == :count && "bg-slate-300 text-slate-950",
            @sort != :count && "text-slate-700 hover:bg-slate-200"
          ]}
        >
          count
        </button>
        <button
          type="button"
          phx-click="set_sort"
          phx-value-sort="alpha"
          class={[
            "rounded-md px-2 py-1 font-medium",
            @sort == :alpha && "bg-slate-300 text-slate-950",
            @sort != :alpha && "text-slate-700 hover:bg-slate-200"
          ]}
        >
          alpha
        </button>
      </div>

      <div class="mb-6">
        <form phx-change="run_search" phx-submit="run_search" class="w-full">
          <%= text_input :query_field,
              :query,
              placeholder: "Search domains",
              autofocus: true,
              autocomplete: "off",
              class: "block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-sm text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200",
              "phx-debounce": "200",
              value: @search %>
        </form>
      </div>

      <div class="overflow-hidden rounded-lg border border-slate-400 bg-slate-100 shadow-sm">
        <%= if @domains == [] do %>
          <div class="px-6 py-12 text-center text-sm text-slate-700">
            <%= if @search == "", do: "No bookmark domains found.", else: "No domains match \"#{@search}\"." %>
          </div>
        <% else %>
          <div class="divide-y divide-slate-300">
            <%= for domain <- @domains do %>
              <div
                id={"domain-#{domain.domain}"}
                class="flex flex-col gap-3 px-4 py-4 transition hover:bg-slate-200 sm:flex-row sm:items-start sm:justify-between"
              >
                <div class="min-w-0 sm:max-w-xs">
                  <.link
                    navigate={Routes.site_index_path(@socket, :index, q: Bookmarks.query_fragment("domain", domain.domain))}
                    class="block truncate text-sm font-semibold text-slate-950 hover:text-sky-700"
                  >
                    <%= domain.domain %>
                  </.link>
                  <div class="mt-1 text-xs text-slate-700">
                    <%= domain.count %> <%= if domain.count == 1, do: "bookmark", else: "bookmarks" %>
                  </div>
                </div>

                <div class="flex flex-wrap items-center gap-2 sm:justify-end">
                  <%= if domain.tags == [] do %>
                    <span class="text-sm text-slate-700">No tags assigned.</span>
                  <% else %>
                    <%= for tag <- domain.tags do %>
                      <.link
                        navigate={Routes.site_index_path(@socket, :index, q: domain_tag_query(domain.domain, tag.name))}
                        class="rounded-full bg-slate-200 px-3 py-1 text-xs font-medium text-slate-700 hover:bg-sky-50 hover:text-sky-700"
                      >
                        <%= tag.name %> <span class="text-slate-500"><%= tag.count %></span>
                      </.link>
                    <% end %>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <nav :if={@total_pages > 1} class="border-t border-slate-300 px-4 py-3">
            <ul class="flex flex-wrap items-center gap-1 text-sm">
              <li>
                <a
                  class={[
                    "rounded-md px-3 py-2 font-medium text-slate-800 hover:bg-slate-200 hover:text-slate-950",
                    @page_number <= 1 && "pointer-events-none text-slate-400 hover:bg-transparent"
                  ]}
                  href="#"
                  phx-click="nav"
                  phx-value-page={@page_number - 1}
                >
                  Previous
                </a>
              </li>
              <%= for idx <- 1..@total_pages do %>
                <li>
                  <a
                    class={[
                      "rounded-md px-3 py-2 font-medium text-slate-800 hover:bg-slate-200 hover:text-slate-950",
                      @page_number == idx && "pointer-events-none bg-sky-50 text-sky-700"
                    ]}
                    href="#"
                    phx-click="nav"
                    phx-value-page={idx}
                  >
                    <%= idx %>
                  </a>
                </li>
              <% end %>
              <li>
                <a
                  class={[
                    "rounded-md px-3 py-2 font-medium text-slate-800 hover:bg-slate-200 hover:text-slate-950",
                    @page_number >= @total_pages && "pointer-events-none text-slate-400 hover:bg-transparent"
                  ]}
                  href="#"
                  phx-click="nav"
                  phx-value-page={@page_number + 1}
                >
                  Next
                </a>
              </li>
            </ul>
          </nav>
        <% end %>
      </div>
    </section>
    """
  end

  defp domain_tag_query(domain, tag) do
    Enum.join(
      [Bookmarks.query_fragment("domain", domain), Bookmarks.query_fragment("tag", tag)],
      " "
    )
  end
end
