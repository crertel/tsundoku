defmodule TsundokuWeb.ImportLive.Index do
  use TsundokuWeb, :live_view

  alias Tsundoku.Bookmarks

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign_defaults(session, socket)
     |> assign(
       page_title: "Import bookmarks",
       last_import: nil
     )
     |> allow_upload(:bookmark_import,
       accept: ~w(.html),
       max_entries: 1,
       auto_upload: true,
       max_file_size: 32_000_000
     )}
  end

  @impl true
  def handle_event("validate-upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("upload-bookmark", _params, socket) do
    [result] =
      consume_uploaded_entries(socket, :bookmark_import, fn %{path: path}, _entry ->
        {:ok, tags, urls} = Bookmarks.import_from_file(path)
        :ok = Bookmarks.load_urls(tags, urls, socket.assigns.current_user.id)
        {:ok, %{tag_count: MapSet.size(tags), url_count: length(urls)}}
      end)

    {:noreply,
     socket
     |> assign(:last_import, result)
     |> put_flash(
       :info,
       "Imported #{result.url_count} bookmarks across #{result.tag_count} tags."
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-3xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-6">
        <h1 class="text-2xl font-semibold text-slate-950">Import bookmarks</h1>
        <p class="mt-1 text-sm text-slate-700">
          Upload a browser-exported <code>bookmarks.html</code>
          file. Tags are read from the folder structure.
        </p>
      </div>

      <div class="rounded-lg border border-slate-400 bg-slate-100 p-6 shadow-sm">
        <%= for entry <- @uploads.bookmark_import.entries do %>
          <div class="mb-3 text-sm text-slate-800">
            <%= entry.client_name %>
            <progress class="ml-2 align-middle" max="100" value={entry.progress} />
          </div>
        <% end %>

        <%= for {_ref, msg} <- @uploads.bookmark_import.errors do %>
          <div class="mb-3 text-sm text-red-700"><%= msg %></div>
        <% end %>

        <form
          id="import-bookmark-form"
          phx-submit="upload-bookmark"
          phx-change="validate-upload"
          class="flex flex-col gap-3 sm:flex-row sm:items-center"
        >
          <.live_file_input
            upload={@uploads.bookmark_import}
            class="block w-full text-sm text-slate-800 file:mr-4 file:rounded-md file:border-0 file:bg-slate-200 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-slate-700 hover:file:bg-slate-200"
          />
          <%= submit "Import",
            class:
              "rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700" %>
        </form>
      </div>

      <div :if={@last_import} class="mt-6 text-sm text-slate-700">
        Last import: {@last_import.url_count} bookmarks across {@last_import.tag_count} tags.
        <.link navigate={~p"/sites"} class="font-medium text-sky-700 hover:text-sky-900">
          View sites
        </.link>
      </div>
    </section>
    """
  end
end
