defmodule TsundokuWeb.ImportLive.Index do
  use TsundokuWeb, :live_view

  alias Tsundoku.Bookmarks

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign_defaults(session, socket)
     |> assign(
       page_title: "Import bookmarks",
       job_id: nil,
       progress: nil,
       last_import: nil
     )
     |> allow_upload(:bookmark_import,
       accept: ~w(.html),
       max_entries: 1,
       auto_upload: true,
       max_file_size: 64_000_000
     )}
  end

  @impl true
  def handle_event("validate-upload", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("upload-bookmark", _params, socket) do
    user_id = socket.assigns.current_user.id

    [job] =
      consume_uploaded_entries(socket, :bookmark_import, fn %{path: path}, _entry ->
        {:ok, tags, urls} = Bookmarks.import_from_file(path)

        job_args = %{
          "user_id" => user_id,
          "tags" => MapSet.to_list(tags),
          "urls" =>
            Enum.map(urls, fn {bm_tags, bm_url, bm_title} ->
              %{"tags" => bm_tags, "url" => bm_url, "title" => bm_title}
            end)
        }

        {:ok, %Oban.Job{id: job_id}} =
          job_args
          |> Tsundoku.Workers.ImportBookmarks.new()
          |> Oban.insert()

        {:ok, %{job_id: job_id, tag_count: MapSet.size(tags), url_count: length(urls)}}
      end)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Tsundoku.PubSub, "imports:job:#{job.job_id}")
    end

    {:noreply,
     socket
     |> assign(:job_id, job.job_id)
     |> assign(:progress, %{processed: 0, total: job.url_count, stage: "queued"})
     |> assign(:last_import, nil)
     |> put_flash(:info, "Importing #{job.url_count} bookmarks in the background…")}
  end

  @impl true
  def handle_info({:import_progress, progress}, socket) do
    {:noreply, assign(socket, :progress, Map.update!(progress, :stage, &to_string/1))}
  end

  @impl true
  def handle_info({:import_complete, %{sites_inserted: sites, tags_inserted: tags}}, socket) do
    {:noreply,
     socket
     |> assign(:progress, nil)
     |> assign(:last_import, %{sites_inserted: sites, tags_inserted: tags})
     |> put_flash(:info, "Imported #{sites} new bookmarks and #{tags} new tags.")}
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

      <div :if={@progress} class="mt-6 rounded-lg border border-slate-300 bg-white p-4 shadow-sm">
        <div class="mb-2 text-sm font-medium text-slate-800">
          {@progress.stage |> String.capitalize()}: {@progress.processed} / {@progress.total}
        </div>
        <progress
          class="w-full"
          max={max(@progress.total, 1)}
          value={@progress.processed}
        />
      </div>

      <div :if={@last_import} class="mt-6 text-sm text-slate-700">
        Imported {@last_import.sites_inserted} new bookmarks and {@last_import.tags_inserted} new tags.
        <.link navigate={~p"/sites"} class="font-medium text-sky-700 hover:text-sky-900">
          View sites
        </.link>
      </div>
    </section>
    """
  end
end
