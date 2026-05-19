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
     |> assign(:merge_dest, "")
     |> assign(:bookmark_count, Bookmarks.count_sites_for_tag(tag))
     |> assign(:co_tags, Bookmarks.list_co_occurring_tags(tag, limit: 20))
     |> assign(:monthly_counts, fill_monthly_gaps(Bookmarks.site_count_by_month_for_tag(tag)))}
  end

  # Fills missing months between the first and last sampled month with zeros
  # so the sparkline shows a continuous timeline.
  defp fill_monthly_gaps([]), do: []

  defp fill_monthly_gaps(entries) do
    counts = Map.new(entries, fn %{month: m, count: c} -> {m, c} end)
    first = entries |> List.first() |> Map.get(:month)
    last = entries |> List.last() |> Map.get(:month)

    first
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&(Date.compare(&1, last) != :gt))
    |> Enum.map(fn m -> %{month: m, count: Map.get(counts, m, 0)} end)
  end

  defp sparkline_points(entries, width, height) do
    case entries do
      [] ->
        ""

      [%{count: c}] ->
        # Single point: a flat baseline so the line is still visible.
        "0,#{height} #{width},#{height - point_y(c, c, height)}"

      _ ->
        max_count = entries |> Enum.map(& &1.count) |> Enum.max()
        n = length(entries)
        step = if n > 1, do: width / (n - 1), else: 0

        entries
        |> Enum.with_index()
        |> Enum.map(fn {%{count: c}, i} ->
          "#{Float.round(i * step, 2)},#{height - point_y(c, max_count, height)}"
        end)
        |> Enum.join(" ")
    end
  end

  defp point_y(_count, 0, _height), do: 0
  defp point_y(count, max, height), do: count / max * (height - 4) + 2

  defp format_month(%Date{} = d), do: Calendar.strftime(d, "%b %Y")

  defp tag_filter_path(socket, name) do
    Routes.site_index_path(socket, :index, q: Bookmarks.query_fragment("tag", name))
  end

  defp tag_and_filter_path(socket, name1, name2) do
    Routes.site_index_path(
      socket,
      :index,
      q:
        [
          Bookmarks.query_fragment("tag", name1),
          Bookmarks.query_fragment("tag", name2)
        ]
        |> Enum.join(" ")
    )
  end

  defp page_title(:show), do: "Show Tag"
  defp page_title(:edit), do: "Edit Tag"

  @impl true
  def handle_event("delete_tagged_sites", %{"confirm" => %{"name" => typed}}, socket) do
    tag = socket.assigns.tag

    if String.trim(typed) == tag.name do
      {count, _} = Bookmarks.delete_sites_for_tag(tag)

      {:noreply,
       socket
       |> put_flash(:info, "Deleted #{count} bookmark(s) tagged #{inspect(tag.name)}.")
       |> assign(:bookmark_count, Bookmarks.count_sites_for_tag(tag))
       |> assign(:co_tags, Bookmarks.list_co_occurring_tags(tag, limit: 20))}
    else
      {:noreply,
       put_flash(socket, :error, "Confirmation didn't match the tag name. Nothing deleted.")}
    end
  end

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
            <.link
              navigate={tag_filter_path(@socket, @tag.name)}
              class="inline-flex max-w-full items-center truncate rounded-full bg-slate-200 px-3 py-1 text-sm font-medium text-slate-700 hover:bg-sky-50 hover:text-sky-700"
            >
              <%= @tag.name %>
            </.link>
          </dd>

          <dt class="text-sm font-medium text-slate-700">Bookmarks</dt>
          <dd class="text-sm text-slate-800">
            <.link navigate={tag_filter_path(@socket, @tag.name)} class="text-sky-700 hover:text-sky-900">
              <%= @bookmark_count %>
              <%= if @bookmark_count == 1, do: "bookmark", else: "bookmarks" %>
            </.link>
          </dd>

          <dt :if={@tag.description not in [nil, ""]} class="text-sm font-medium text-slate-700">
            Description
          </dt>
          <dd :if={@tag.description not in [nil, ""]} class="text-sm text-slate-800 whitespace-pre-line">
            <%= @tag.description %>
          </dd>
        </dl>
      </div>

      <div :if={length(@monthly_counts) > 1} class="mb-6 rounded-lg border border-slate-400 bg-slate-100 p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-slate-950">Saves over time</h2>
        <p class="mt-1 text-sm text-slate-700">
          Bookmarks tagged <strong><%= @tag.name %></strong> per month,
          from <%= format_month(List.first(@monthly_counts).month) %>
          to <%= format_month(List.last(@monthly_counts).month) %>.
        </p>
        <svg viewBox="0 0 320 60" class="mt-4 h-16 w-full" preserveAspectRatio="none">
          <polyline
            fill="none"
            stroke="#0284c7"
            stroke-width="2"
            stroke-linejoin="round"
            stroke-linecap="round"
            points={sparkline_points(@monthly_counts, 320, 60)}
          />
        </svg>
      </div>

      <div :if={@co_tags != []} class="mb-6 rounded-lg border border-slate-400 bg-slate-100 p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-slate-950">Often appears with</h2>
        <p class="mt-1 text-sm text-slate-700">
          Tags most frequently used together with <strong><%= @tag.name %></strong>.
          Click a tag to view the bookmarks carrying both.
        </p>
        <div class="mt-4 flex flex-wrap items-center gap-2">
          <%= for co <- @co_tags do %>
            <.link
              navigate={tag_and_filter_path(@socket, @tag.name, co.name)}
              class="inline-flex items-center gap-2 rounded-full bg-slate-200 px-3 py-1 text-xs font-medium text-slate-700 hover:bg-sky-50 hover:text-sky-700"
            >
              <%= co.name %>
              <span class="rounded-full bg-white/70 px-2 text-[10px] font-semibold text-slate-600">
                <%= co.count %>
              </span>
            </.link>
          <% end %>
        </div>
      </div>

      <div :if={@bookmark_count > 0} class="mb-6 rounded-lg border border-rose-300 bg-rose-50 p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-rose-900">Delete all bookmarks with this tag</h2>
        <p class="mt-1 text-sm text-rose-900">
          Permanently deletes every bookmark you have tagged
          <strong><%= @tag.name %></strong>. The tag itself is kept.
          To confirm, type the tag name below. This cannot be undone.
        </p>

        <form phx-submit="delete_tagged_sites" class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center">
          <input
            type="text"
            name="confirm[name]"
            placeholder={"Type \"#{@tag.name}\" to confirm"}
            required
            autocomplete="off"
            class="block w-full rounded-md border border-rose-400 bg-white px-3 py-2 text-sm text-slate-950 shadow-sm focus:border-rose-500 focus:outline-none focus:ring-2 focus:ring-rose-200 sm:w-80"
          />
          <button
            type="submit"
            data-confirm={"Delete every bookmark tagged \"#{@tag.name}\"? This cannot be undone."}
            class="rounded-md bg-rose-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-700"
          >
            Delete <%= @bookmark_count %> bookmark<%= if @bookmark_count == 1, do: "", else: "s" %>
          </button>
        </form>
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
