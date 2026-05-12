defmodule BookmarkServerWeb.PageLive do
  use BookmarkServerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, query: "", results: %{})}
  end

  @impl true
  def handle_event("suggest", %{"q" => query}, socket) do
    {:noreply, assign(socket, results: search(query), query: query)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    case search(query) do
      %{^query => vsn} ->
        {:noreply, redirect(socket, external: "https://hexdocs.pm/#{query}/#{vsn}")}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "No dependencies found matching \"#{query}\"")
         |> assign(results: %{}, query: query)}
    end
  end

  defp search(query) do
    if not BookmarkServerWeb.Endpoint.config(:code_reloader) do
      raise "action disabled when not in development"
    end

    for {app, desc, vsn} <- Application.started_applications(),
        app = to_string(app),
        String.starts_with?(app, query) and not List.starts_with?(desc, ~c"ERTS"),
        into: %{},
        do: {app, vsn}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-7xl px-4 py-10 sm:px-6 lg:px-8">
      <div class="rounded-lg border border-slate-400 bg-slate-100 p-6 shadow-sm">
        <h1 class="text-2xl font-semibold text-slate-950">Bookmark Server</h1>
        <form phx-change="suggest" phx-submit="search" class="mt-6 max-w-xl">
        <input type="text" name="q" value={@query} placeholder="Live dependency search" list="results" autocomplete="off" class="block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200"/>
        <datalist id="results">
          <%= for {app, _vsn} <- @results do %>
            <option value={app}><%= app %></option>
          <% end %>
        </datalist>
      </form>
      </div>
    </section>
    """
  end
end
