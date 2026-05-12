defmodule BookmarkServerWeb.SiteLive.Index do
  use BookmarkServerWeb, :live_view

  alias BookmarkServer.Bookmarks
  alias BookmarkServer.Bookmarks.Site

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign_defaults(session, socket)
     |> assign(
       uploaded_files: [],
       available_tags: [],
       available_domains: [],
       parsed_query: Bookmarks.parse_site_query(""),
       search_suggestions: [],
       sites: [],
       page_number: 1,
       page_size: 50,
       search: "",
       tag_search: "",
       total_entries: 0,
       total_pages: 0
     )
     |> allow_upload(:bookmark_import,
       accept: ~w(.html),
       max_entries: 1,
       auto_upload: true,
       max_file_size: 32_000_000
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Site")
    |> assign(:site, Bookmarks.get_site!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Site")
    |> assign(:site, %Site{})
  end

  defp apply_action(socket, :index, params) do
    query = params["q"] || legacy_query(params)

    assigns =
      get_and_assign_page(
        params["page"] || 1,
        query,
        socket.assigns.current_user.id
      )

    socket
    |> assign(:page_title, "Listing Sites")
    |> assign(:available_tags, Bookmarks.list_tags() |> Enum.map(& &1.name))
    |> assign(:available_domains, Bookmarks.list_domain_names(socket.assigns.current_user.id))
    |> assign(:site, nil)
    |> assign(assigns)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    site = Bookmarks.get_site!(id)
    {:ok, _} = Bookmarks.delete_site(site)

    assigns =
      get_and_assign_page(
        socket.assigns.page_number,
        socket.assigns.search,
        socket.assigns.current_user.id
      )

    {:noreply,
     socket
     |> assign(assigns)}
  end

  @impl true
  def handle_event("validate-upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("upload-bookmark", _params, socket) do
    socket
    |> consume_uploaded_entries(:bookmark_import, fn %{path: path}, _entry ->
      {:ok, tags, urls} = BookmarkServer.Bookmarks.import_from_file(path)
      :ok = BookmarkServer.Bookmarks.load_urls(tags, urls, socket.assigns.current_user.id)
      {:ok, :ok}
    end)

    assigns =
      get_and_assign_page(
        socket.assigns.page_number,
        socket.assigns.search,
        socket.assigns.current_user.id
      )

    {:noreply, socket |> assign(assigns)}
  end

  @impl true
  def handle_event("nav", %{"page" => page}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         Routes.site_index_path(socket, :index,
           page: page,
           q: socket.assigns.search
         )
     )}
  end

  @impl true
  def handle_event("run_search", %{"query_field" => %{"query" => search}}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         Routes.site_index_path(socket, :index,
           page: 1,
           q: search
         )
     )}
  end

  @impl true
  def handle_event("add_filter_tag", %{"tag" => tag}, socket) do
    {:noreply,
     socket
     |> assign(page_number: 1)
     |> push_patch(
       to:
         Routes.site_index_path(socket, :index,
           page: 1,
           q: append_query_fragment(socket.assigns.search, "tag", tag)
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
           Routes.site_index_path(socket, :index,
             page: 1,
             q: append_query_fragment(socket.assigns.search, "tag", suggested_tag)
           )
       )}
    end
  end

  def get_and_assign_page(page_number, search, user_id) do
    search_string = String.trim(search)
    parsed_query = Bookmarks.parse_site_query(search_string)

    query_params = %{
      query: search_string,
      created_by: user_id
    }

    %{
      entries: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    } = Bookmarks.search_and_paginate_sites(query_params, page: page_number, page_size: 50)

    [
      sites: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages,
      parsed_query: parsed_query,
      search: search_string
    ]
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
      <div class="mb-6 grid gap-4 lg:grid-cols-[1fr_auto] lg:items-end">
        <div>
          <h1 class="text-2xl font-semibold text-slate-950">Sites</h1>
          <p class="mt-1 text-sm text-slate-700"><%= @total_entries %> saved bookmarks</p>
        </div>

        <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
          <form phx-change="run_search" class="w-full sm:w-96">
            <%= text_input :query_field,
                :query,
                placeholder: ~s(Search, tag:"reading", domain:example.com),
                autofocus: true,
                class: "block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-sm text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200",
                list: "site-search-suggestions",
                "phx-debounce": "500" , value: @search%>
            <datalist id="site-search-suggestions">
              <%= for suggestion <- search_suggestions(@search, @available_tags, @available_domains) do %>
                <option value={suggestion}/>
              <% end %>
            </datalist>
          </form>

          <.link patch={Routes.site_index_path(@socket, :new)} class="inline-flex items-center justify-center rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700">
            New Site
          </.link>
        </div>
      </div>

      <div class="mb-6 rounded-lg border border-slate-400 bg-slate-100 p-4 shadow-sm">
        <div class="flex flex-wrap items-center gap-2">
          <%= for text <- @parsed_query.text do %>
            <span class="rounded-full bg-slate-200 px-3 py-1 text-sm font-medium text-slate-700"><%= text %></span>
          <% end %>
          <%= for tag <- @parsed_query.tags do %>
            <span class="rounded-full bg-sky-50 px-3 py-1 text-sm font-medium text-sky-700">tag:<%= tag %></span>
          <% end %>
          <%= for domain <- @parsed_query.domains do %>
            <span class="rounded-full bg-sky-50 px-3 py-1 text-sm font-medium text-sky-700">domain:<%= domain %></span>
          <% end %>
          <%= for url <- @parsed_query.urls do %>
            <span class="rounded-full bg-sky-50 px-3 py-1 text-sm font-medium text-sky-700">url:<%= url %></span>
          <% end %>
          <%= if @search == "" do %>
            <span class="text-sm text-slate-700">Use free text, <code>tag:name</code>, <code>domain:example.com</code>, or <code>url:text</code>.</span>
          <% end %>
        </div>
      </div>

    <%= if @live_action in [:new, :edit] do %>
      <%= live_modal @socket, BookmarkServerWeb.SiteLive.FormComponent,
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
              <div class="min-w-0 flex-1">
                  <a href={ site.url } class="block truncate text-sm font-semibold text-slate-950 hover:text-sky-700" target="_blank">
                    <%= if site.display_name == "" do%>
                      <%= site.url %>
                    <% else  %>
                      <%= site.display_name %>
                    <% end %>
                  </a>
                  <div class="mt-1 truncate text-xs text-slate-700"><%= site.url %></div>
              </div>
            </div>
            <div class="mt-3 flex flex-wrap items-center gap-2 pl-24">
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

    <div class="mt-6 rounded-lg border border-slate-400 bg-slate-100 p-4 shadow-sm">
      <h2 class="text-sm font-semibold text-slate-950">Import bookmarks</h2>
      <%= for entry <- @uploads.bookmark_import.entries do %>
      <div class="mt-3 text-sm text-slate-800">
        <%= entry.client_name %> <progress class="ml-2 align-middle" max="100" value={entry.progress} />
        </div>
      <% end %>

      <%= for {_ref, msg} <- @uploads.bookmark_import.errors do %>
        <div class="mt-3 text-sm text-red-700"><%= msg %></div>
      <% end %>

      <form id="import-bookmark-form" phx-submit="upload-bookmark" phx-change="validate-upload" class="mt-3 flex flex-col gap-3 sm:flex-row sm:items-center">
        <.live_file_input upload={@uploads.bookmark_import} class="block w-full text-sm text-slate-800 file:mr-4 file:rounded-md file:border-0 file:bg-slate-200 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-slate-700 hover:file:bg-slate-200" />
        <%= submit "Import", class: "rounded-md border border-slate-400 bg-slate-50 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200" %>
      </form>
    </div>
    </section>
    """
  end
end
