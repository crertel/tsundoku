defmodule TsundokuWeb.SiteLive.Index do
  use TsundokuWeb, :live_view

  alias Tsundoku.Bookmarks
  alias Tsundoku.Bookmarks.Site
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, session, socket) do
    socket = assign_defaults(session, socket)

    {:ok,
     socket
     |> subscribe_to_bookmarks(socket.assigns.current_user.id)
     |> assign(
       available_tags: [],
       available_domains: [],
       parsed_query: Bookmarks.parse_site_query(""),
       suggestions: [],
       sites: [],
       page_number: 1,
       page_size: 50,
       search: "",
       total_entries: 0,
       total_pages: 0,
       total_unfiltered: 0,
       sort: :recency
     )}
  end

  @impl true
  def handle_info({:bookmarks_event, _kind, _payload}, socket) do
    {:noreply, schedule_bookmarks_refetch(socket)}
  end

  def handle_info(:bookmarks_refetch, socket) do
    {:noreply, reload_index(socket)}
  end

  # Re-runs the current page's data load against the latest DB state.
  # Filter-blind: any bookmarks_event triggers a full refetch of the
  # current page + tags/domains. Future work: only re-query when the
  # changed record could intersect the current parsed_query.
  defp reload_index(socket) do
    user_id = socket.assigns.current_user.id

    page_result =
      Bookmarks.search_sites(
        user_id,
        socket.assigns.parsed_query,
        page: socket.assigns.page_number,
        page_size: socket.assigns.page_size,
        sort: socket.assigns.sort
      )

    assign(socket,
      sites: page_result.entries,
      total_entries: page_result.total_entries,
      total_pages: page_result.total_pages,
      available_tags: Bookmarks.list_user_tag_names(user_id),
      available_domains: Bookmarks.list_user_domain_names(user_id),
      total_unfiltered: Bookmarks.count_user_sites(user_id),
      bookmarks_refetch_timer: nil
    )
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    site = Bookmarks.get_site!(id) |> ensure_owner!(socket.assigns.current_user)

    socket
    |> assign(:page_title, "Edit Site")
    |> assign(:site, site)
    |> assign_new(:search_input, fn -> "" end)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Site")
    |> assign(:site, %Site{})
    |> assign_new(:search_input, fn -> "" end)
  end

  defp apply_action(socket, :index, params) do
    user_id = socket.assigns.current_user.id
    query = params["q"] || legacy_query(params)
    search_string = String.trim(query)
    parsed_query = Bookmarks.parse_site_query(search_string)
    page = params["page"] || 1
    sort = parse_sort(params["sort"])

    page_result =
      Bookmarks.search_sites(user_id, parsed_query, page: page, page_size: 50, sort: sort)

    available_tags = Bookmarks.list_user_tag_names(user_id)
    available_domains = Bookmarks.list_user_domain_names(user_id)
    total_unfiltered = Bookmarks.count_user_sites(user_id)
    initial_input = parsed_query.bare_phrase

    socket =
      socket
      |> assign(:page_title, "Listing Sites")
      |> assign(:available_tags, available_tags)
      |> assign(:available_domains, available_domains)
      |> assign(:site, nil)
      |> assign(:sort, sort)
      |> assign(:total_unfiltered, total_unfiltered)
      |> assign(
        sites: page_result.entries,
        page_number: page_result.page_number,
        page_size: page_result.page_size,
        total_entries: page_result.total_entries,
        total_pages: page_result.total_pages,
        parsed_query: parsed_query,
        search: search_string
      )
      |> assign_new(:search_input, fn -> initial_input end)

    assign(
      socket,
      :suggestions,
      search_suggestions(socket.assigns.search_input, available_tags, available_domains)
    )
  end

  defp parse_sort("alpha"), do: :alpha
  defp parse_sort(_), do: :recency

  # Build a /sites path that preserves the current sort. Sort is taken
  # explicitly from `params[:sort]` — callers in handlers pass
  # `socket.assigns.sort`; callers in templates pass `@sort`.
  defp index_path(socket, params) do
    sort_param =
      case Keyword.get(params, :sort) do
        :alpha -> "alpha"
        "alpha" -> "alpha"
        _ -> nil
      end

    base = [page: Keyword.get(params, :page, 1), q: Keyword.get(params, :q, "")]
    full = if sort_param, do: base ++ [sort: sort_param], else: base

    Routes.site_index_path(socket, :index, full)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    site = Bookmarks.get_site!(id) |> ensure_owner!(socket.assigns.current_user)
    {:ok, _} = Bookmarks.delete_site(site)

    page_result =
      Bookmarks.search_sites(
        socket.assigns.current_user.id,
        socket.assigns.parsed_query,
        page: socket.assigns.page_number,
        page_size: socket.assigns.page_size
      )

    {:noreply,
     assign(socket,
       sites: page_result.entries,
       total_entries: page_result.total_entries,
       total_pages: page_result.total_pages
     )}
  end

  @impl true
  def handle_event("nav", %{"page" => page}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         index_path(socket,
           page: page,
           q: socket.assigns.search,
           sort: socket.assigns.sort
         )
     )}
  end

  @impl true
  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply,
     push_patch(socket,
       to: index_path(socket, page: 1, q: socket.assigns.search, sort: sort)
     )}
  end

  @impl true
  def handle_event("update_input", %{"query_field" => %{"query" => text}}, socket) do
    suggestions =
      search_suggestions(text, socket.assigns.available_tags, socket.assigns.available_domains)

    {:noreply, assign(socket, search_input: text, suggestions: suggestions)}
  end

  @impl true
  def handle_event("commit_search", %{"query_field" => %{"query" => text}}, socket) do
    case append_typed_to_query(socket.assigns.search, text) do
      {:unchanged, _} ->
        {:noreply, socket}

      {:patched, new_q} ->
        {:noreply,
         socket
         |> assign(:search_input, "")
         |> push_patch(to: index_path(socket, page: 1, q: new_q, sort: socket.assigns.sort))}
    end
  end

  @impl true
  def handle_event("remove_filter", %{"type" => type, "value" => value}, socket) do
    new_query = Bookmarks.remove_filter(socket.assigns.search, type, value)

    {:noreply,
     push_patch(socket,
       to: index_path(socket, page: 1, q: new_query, sort: socket.assigns.sort)
     )}
  end

  @impl true
  def handle_event("apply_suggestion", %{"query" => suggestion}, socket) do
    case append_typed_to_query(socket.assigns.search, suggestion) do
      {:unchanged, _} ->
        {:noreply, socket}

      {:patched, new_q} ->
        {:noreply,
         socket
         |> assign(:search_input, "")
         |> push_patch(to: index_path(socket, page: 1, q: new_q, sort: socket.assigns.sort))}
    end
  end

  @impl true
  def handle_event("add_filter_tag", %{"tag" => tag}, socket) do
    {:noreply,
     socket
     |> assign(page_number: 1)
     |> push_patch(
       to:
         index_path(socket,
           page: 1,
           q: append_query_fragment(socket.assigns.search, "tag", tag),
           sort: socket.assigns.sort
         )
     )}
  end

  @impl true
  def handle_event("add_filter_tag", %{"filter_tag" => %{"tag" => suggested_tag}}, socket) do
    if suggested_tag not in socket.assigns.available_tags do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(page_number: 1)
       |> push_patch(
         to:
           index_path(socket,
             page: 1,
             q: append_query_fragment(socket.assigns.search, "tag", suggested_tag),
             sort: socket.assigns.sort
           )
       )}
    end
  end

  defp legacy_query(%{"search" => search, "tags" => tags}) when is_list(tags) do
    [search | Enum.map(tags, &Bookmarks.query_fragment("tag", &1))]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp legacy_query(%{"search" => search}), do: search

  defp legacy_query(%{"tags" => tags}) when is_list(tags),
    do: Enum.map_join(tags, " ", &Bookmarks.query_fragment("tag", &1))

  defp legacy_query(_params), do: ""

  defp append_query_fragment(query, field, value) do
    [String.trim(query || ""), Bookmarks.query_fragment(field, value)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp append_typed_to_query(current_q, typed) do
    typed_tokens = typed |> Bookmarks.parse_site_query() |> serialize_as_filter_tokens()

    if typed_tokens == [] do
      {:unchanged, current_q}
    else
      new_q =
        [String.trim(current_q || "") | typed_tokens]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")

      {:patched, new_q}
    end
  end

  defp serialize_as_filter_tokens(parsed) do
    bare_token =
      if parsed.bare_phrase == "",
        do: [],
        else: [Bookmarks.query_fragment("title", parsed.bare_phrase)]

    metadata_token =
      case parsed[:has_metadata] do
        true -> ["metadata:has"]
        false -> ["metadata:missing"]
        _ -> []
      end

    status_token =
      case parsed[:crawl_status] do
        nil -> []
        value -> ["status:" <> value]
      end

    bare_token ++
      Enum.map(parsed.titles, &Bookmarks.query_fragment("title", &1)) ++
      Enum.map(parsed.tags, &Bookmarks.query_fragment("tag", &1)) ++
      Enum.map(parsed.domains, &Bookmarks.query_fragment("domain", &1)) ++
      Enum.map(parsed.urls, &Bookmarks.query_fragment("url", &1)) ++
      metadata_token ++
      status_token ++
      Enum.map(parsed.exclude_titles, &("-" <> Bookmarks.query_fragment("title", &1))) ++
      Enum.map(parsed.exclude_tags, &("-" <> Bookmarks.query_fragment("tag", &1))) ++
      Enum.map(parsed.exclude_domains, &("-" <> Bookmarks.query_fragment("domain", &1))) ++
      Enum.map(parsed.exclude_urls, &("-" <> Bookmarks.query_fragment("url", &1)))
  end

  defp search_suggestions(query, tags, domains) do
    {prefix, fragment} = query_prefix_and_fragment(query)
    normalized_fragment = String.downcase(fragment)

    cond do
      String.starts_with?(normalized_fragment, "tag:") ->
        suggest_field(prefix, "tag", field_value_fragment(fragment, "tag"), tags)

      String.starts_with?(normalized_fragment, "domain:") ->
        suggest_field(prefix, "domain", field_value_fragment(fragment, "domain"), domains)

      String.starts_with?(normalized_fragment, "site:") ->
        suggest_field(prefix, "site", field_value_fragment(fragment, "site"), domains)

      String.starts_with?(normalized_fragment, "url:") ->
        [prefix <> "url:"]

      true ->
        field_suggestions =
          ["tag:", "domain:", "url:"]
          |> Enum.filter(&String.starts_with?(&1, normalized_fragment))
          |> Enum.map(&(prefix <> &1))

        value_suggestions =
          suggest_field(prefix, "tag", fragment, tags) ++
            suggest_field(prefix, "domain", fragment, domains)

        (field_suggestions ++ value_suggestions)
        |> Enum.uniq()
        |> Enum.take(12)
    end
  end

  defp query_prefix_and_fragment(query) do
    query = query || ""

    case Regex.run(~r/^(.*\s)?(\S*)$/, query) do
      [_, nil, fragment] -> {"", fragment}
      [_, prefix, fragment] -> {prefix, fragment}
      _ -> {"", query}
    end
  end

  defp field_value_fragment(fragment, field) do
    fragment
    |> String.split(":", parts: 2)
    |> case do
      [typed_field, value] ->
        if String.downcase(typed_field) == field, do: value, else: fragment

      _ ->
        fragment
    end
  end

  defp suggest_field(prefix, field, fragment, values) do
    fragment =
      fragment
      |> String.trim()
      |> String.trim_leading(~s("))
      |> String.trim_trailing(~s("))
      |> String.downcase()

    values
    |> Enum.filter(&(fragment == "" or String.contains?(String.downcase(&1), fragment)))
    |> Enum.take(12)
    |> Enum.map(&(prefix <> Bookmarks.query_fragment(field, &1)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 class="text-2xl font-semibold text-slate-950">Sites</h1>
          <p class="mt-1 text-sm text-slate-700">
            <%= if @search == "" do %>
              <%= @total_entries %> saved bookmarks
            <% else %>
              <%= @total_entries %> filtered bookmarks (of <%= @total_unfiltered %>)
            <% end %>
          </p>
        </div>
        <.link patch={Routes.site_index_path(@socket, :new)} class="inline-flex items-center justify-center self-start rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700 sm:self-auto">
          New Site
        </.link>
      </div>

      <div class="mb-4 flex items-center justify-end gap-2 text-xs text-slate-600">
        <span>Sort:</span>
        <button
          type="button"
          phx-click="set_sort"
          phx-value-sort="recency"
          class={[
            "rounded-md px-2 py-1 font-medium",
            @sort == :recency && "bg-slate-300 text-slate-950",
            @sort != :recency && "text-slate-700 hover:bg-slate-200"
          ]}
        >
          recency
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
        <div class="group relative w-full">
          <form id="site-search-form" phx-change="update_input" phx-submit="commit_search">
            <div class="flex gap-2">
              <input
                type="text"
                id="site-search-input"
                name="query_field[query]"
                value={@search_input}
                placeholder={~s(Search title, or tag:name, domain:example.com, url:text)}
                autocomplete="off"
                autofocus
                onkeydown="if (event.key === 'Escape') { this.blur(); } else if (event.key === 'ArrowDown') { event.preventDefault(); document.querySelector('#site-search-suggestions button')?.focus(); }"
                class="block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-sm text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"
              />
              <.link
                :if={@search != ""}
                navigate={~p"/searches/new?query=#{@search}"}
                title="Save this query as a named search"
                class="shrink-0 rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200"
              >
                💾 Save
              </.link>
            </div>
          </form>
          <ul
            id="site-search-suggestions"
            :if={@search_input != "" and @suggestions != [] and @suggestions != [@search_input]}
            class="absolute z-10 mt-1 hidden max-h-72 w-full overflow-auto rounded-md border border-slate-400 bg-slate-50 py-1 text-sm shadow-lg group-focus-within:block"
          >
            <%= for suggestion <- @suggestions do %>
              <li>
                <button
                  type="button"
                  phx-click={JS.push("apply_suggestion", value: %{query: suggestion})}
                  onkeydown="(function(e, el){const b=Array.from(document.querySelectorAll('#site-search-suggestions button'));const i=b.indexOf(el);if(e.key==='ArrowDown'){e.preventDefault();b[i+1]?.focus();}else if(e.key==='ArrowUp'){e.preventDefault();if(i===0){document.getElementById('site-search-input').focus();}else{b[i-1].focus();}}else if(e.key==='Escape'){const inp=document.getElementById('site-search-input');inp.focus();inp.blur();}})(event,this)"
                  class="block w-full px-3 py-2 text-left text-slate-800 hover:bg-slate-200 focus:bg-slate-200 focus:text-slate-950 focus:outline-none hover:text-slate-950"
                >
                  <%= suggestion %>
                </button>
              </li>
            <% end %>
          </ul>
        </div>
      </div>

      <div class="mb-6 rounded-lg border border-slate-400 bg-slate-100 p-4 shadow-sm">
        <div class="flex flex-wrap items-center gap-2">
          <%= for title <- @parsed_query.titles do %>
            <.filter_pill filter_type="title" filter_value={title} color="slate">
              title:<%= title %>
            </.filter_pill>
          <% end %>
          <%= for tag <- @parsed_query.tags do %>
            <.filter_pill filter_type="tag" filter_value={tag} color="sky">
              tag:<%= tag %>
            </.filter_pill>
          <% end %>
          <%= for domain <- @parsed_query.domains do %>
            <.filter_pill filter_type="domain" filter_value={domain} color="sky">
              domain:<%= domain %>
            </.filter_pill>
          <% end %>
          <%= for url <- @parsed_query.urls do %>
            <.filter_pill filter_type="url" filter_value={url} color="sky">
              url:<%= url %>
            </.filter_pill>
          <% end %>
          <%= case @parsed_query[:has_metadata] do %>
            <% true -> %>
              <.filter_pill filter_type="metadata" filter_value="has" color="slate">
                metadata:has
              </.filter_pill>
            <% false -> %>
              <.filter_pill filter_type="metadata" filter_value="missing" color="slate">
                metadata:missing
              </.filter_pill>
            <% _ -> %>
          <% end %>
          <%= if status = @parsed_query[:crawl_status] do %>
            <.filter_pill filter_type="status" filter_value={status} color="slate">
              status:<%= status %>
            </.filter_pill>
          <% end %>
          <span :if={@search == ""} class="text-sm text-slate-500">No filters.</span>
        </div>
      </div>

    <%= if @live_action in [:new, :edit] do %>
      <%= live_modal @socket, TsundokuWeb.SiteLive.FormComponent,
        id: @site.id || :new,
        title: @page_title,
        action: @live_action,
        current_user: @current_user,
        site: @site,
        return_to: Routes.site_index_path(@socket, :index) %>
    <% end %>

    <div id="tags" class="overflow-hidden rounded-lg border border-slate-400 bg-slate-100 shadow-sm">
      <%= if length(@sites) > 0 do %>
        <div class="divide-y divide-slate-300">
        <%= for site <- @sites do %>
          <div id={"site-#{site.id}"} class="px-4 py-4 transition hover:bg-slate-200">
            <div class="flex min-w-0 items-start gap-3">
              <div class="flex shrink-0 items-center gap-2 text-slate-700">
                <.link navigate={Routes.site_show_path(@socket, :show, site)} class="rounded-md p-1 hover:bg-slate-200 hover:text-sky-700" title="View">
                  <Heroicons.information_circle class="h-5 w-5" />
                </.link>
                <.link patch={Routes.site_index_path(@socket, :edit, site)} class="rounded-md p-1 hover:bg-slate-200 hover:text-sky-700" title="Edit">
                  <Heroicons.pencil class="h-5 w-5" />
                </.link>
                <%= link to: "#", phx_click: "delete", phx_value_id: site.id, data: [confirm: "Are you sure?"], class: "rounded-md p-1 hover:bg-red-50 hover:text-red-700", title: "Delete" do %>
                  <Heroicons.x_mark class="h-5 w-5" />
                <% end %>
              </div>
              <div :if={src = favicon_data_url(site)} class="flex shrink-0 items-center pt-0.5">
                <img
                  src={src}
                  alt=""
                  class="h-4 w-4 rounded-sm"
                  loading="lazy"
                />
              </div>
              <div class="min-w-0 flex-1">
                  <div class="flex flex-wrap items-baseline gap-x-2">
                    <a href={ site.url } class="min-w-0 max-w-full truncate text-sm font-semibold text-slate-950 hover:text-sky-700" target="_blank">
                      <%= if site.display_name in [nil, ""] do%>
                        <%= site.url %>
                      <% else  %>
                        <%= site.display_name %>
                      <% end %>
                    </a>
                    <span class="text-xs text-slate-400">·</span>
                    <a
                      href={wayback_url(site.url)}
                      target="_blank"
                      rel="noopener"
                      class="text-xs text-slate-500 hover:text-sky-700"
                      title="Wayback Machine snapshots"
                    >
                      wayback
                    </a>
                    <a
                      href={archive_ph_url(site.url)}
                      target="_blank"
                      rel="noopener"
                      class="text-xs text-slate-500 hover:text-sky-700"
                      title="archive.ph snapshots"
                    >
                      archive.ph
                    </a>
                  </div>
                  <div class="mt-1 truncate text-xs text-slate-700"><%= site.url %></div>
                  <p :if={site.description not in [nil, ""]} class="mt-1 line-clamp-2 text-xs text-slate-600">
                    <%= site.description %>
                  </p>
              </div>
            </div>
            <div class="mt-3 flex flex-wrap items-center gap-2 pl-24">
              <.link
                :if={site.domain}
                patch={index_path(@socket, page: 1, q: append_query_fragment(@search, "domain", site.domain), sort: @sort)}
                class="rounded-full bg-sky-50 px-3 py-1 text-xs font-medium text-sky-700 hover:bg-sky-100"
              >
                domain:<%= site.domain %>
              </.link>
              <.link
                :if={site.crawl_status not in [nil, "ok"]}
                patch={index_path(@socket, page: 1, q: append_query_fragment(@search, "status", site.crawl_status), sort: @sort)}
                class="rounded-full bg-amber-100 px-3 py-1 text-xs font-medium text-amber-800 hover:bg-amber-200"
                title="Crawl status"
              >
                status:<%= site.crawl_status %>
              </.link>
            </div>
            <div class="mt-2 flex flex-wrap items-center gap-2 pl-24">
              <%= if length(site.tags) > 0 do %>
                <%= for tag <- site.tags do %>
                  <button type="button" class="rounded-full bg-slate-200 px-3 py-1 text-xs font-medium text-slate-700 hover:bg-sky-50 hover:text-sky-700" phx-click="add_filter_tag" phx-value-tag={tag.name}>
                    <%= tag.name %>
                  </button>
                <% end %>
              <% else %>
                <span class="text-sm text-slate-700">No tags assigned.</span>
              <% end %>
            </div>
          </div>
        <% end %>
        </div>

      <nav class="border-t border-slate-300 px-4 py-3">
          <ul class="flex flex-wrap items-center gap-1 text-sm">
            <li>
              <%= if @page_number <= 1 do %>
                <a class="pointer-events-none rounded-md px-3 py-2 font-medium text-slate-400"
                 href="#"
                 phx-click="nav"
                 phx-value-page={@page_number - 1}>
                 Previous
                </a>
              <% else %>
              <a class="rounded-md px-3 py-2 font-medium text-slate-800 hover:bg-slate-200 hover:text-slate-950"
                 href="#"
                 phx-click="nav"
                 phx-value-page={@page_number - 1}>
                 Previous
                </a>
              <% end %>

            </li>
        <%= for idx <-  Enum.to_list(1..@total_pages) do %>
            <li>
            <%= if @page_number == idx do %>
              <a class="pointer-events-none rounded-md bg-sky-50 px-3 py-2 font-medium text-sky-700" href="#" phx-click="nav" phx-value-page={idx}>
                <%= idx %>
              </a>
            <% else %>
              <a class="rounded-md px-3 py-2 font-medium text-slate-800 hover:bg-slate-200 hover:text-slate-950" href="#" phx-click="nav" phx-value-page={idx}>
                <%= idx %>
              </a>
            <% end %>
            </li>
        <% end %>
            <li>
              <%= if @page_number >= @total_pages do %>
                <a class="pointer-events-none rounded-md px-3 py-2 font-medium text-slate-400" href="#" phx-click="nav" phx-value-page={@page_number + 1}>
                Next
              </a>
              <% else %>
                <a class="rounded-md px-3 py-2 font-medium text-slate-800 hover:bg-slate-200 hover:text-slate-950" href="#" phx-click="nav" phx-value-page={@page_number + 1}>
                  Next
                </a>
              <% end %>
            </li>
          </ul>
        </nav>
      <% else %>
        <div class="px-6 py-12 text-center text-sm text-slate-700">No sites defined.</div>
      <% end %>
    </div>

    </section>
    """
  end

  attr :filter_type, :string, required: true
  attr :filter_value, :string, required: true
  attr :color, :string, default: "slate"
  slot :inner_block, required: true

  defp filter_pill(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-3 py-1 text-sm font-medium",
      @color == "sky" && "bg-sky-50 text-sky-700",
      @color == "slate" && "bg-slate-200 text-slate-700"
    ]}>
      <span><%= render_slot(@inner_block) %></span>
      <button
        type="button"
        value={@filter_value}
        phx-click="remove_filter"
        phx-value-type={@filter_type}
        phx-value-value={@filter_value}
        title="Remove filter"
        aria-label={"Remove filter #{@filter_type}:#{@filter_value}"}
        class={[
          "-mr-1 inline-flex h-5 w-5 items-center justify-center rounded-full",
          @color == "sky" && "hover:bg-sky-100",
          @color == "slate" && "hover:bg-slate-300"
        ]}
      >
        <Heroicons.x_mark class="h-4 w-4" />
      </button>
    </span>
    """
  end
end
