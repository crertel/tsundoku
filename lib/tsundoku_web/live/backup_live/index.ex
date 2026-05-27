defmodule TsundokuWeb.BackupLive.Index do
  use TsundokuWeb, :live_view

  alias Tsundoku.Bookmarks

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign_defaults(session, socket)
     |> assign(page_title: "Backup & restore", last_restore: nil)
     |> allow_upload(:backup,
       accept: ~w(.json application/json),
       max_entries: 1,
       auto_upload: false,
       max_file_size: 200_000_000
     )}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("restore", _params, socket) do
    user = socket.assigns.current_user

    case consume_uploaded_entries(socket, :backup, &decode_and_restore(&1, &2, user)) do
      [{:ok, summary}] ->
        {:noreply,
         socket
         |> assign(:last_restore, summary)
         |> put_flash(
           :info,
           "Restored: #{summary.tags_created} new tags, " <>
             "#{summary.sites_created} new sites, " <>
             "#{summary.sites_skipped} already-present sites (tags merged)."
         )}

      [{:error, reason}] ->
        {:noreply, put_flash(socket, :error, "Restore failed: #{inspect(reason)}")}

      [] ->
        {:noreply, put_flash(socket, :error, "No file was uploaded.")}
    end
  end

  defp decode_and_restore(%{path: path}, _entry, user) do
    with {:ok, body} <- File.read(path),
         {:ok, dump} <- Jason.decode(body),
         {:ok, summary} <- Bookmarks.restore_user(user, dump) do
      {:ok, {:ok, summary}}
    else
      {:error, %Jason.DecodeError{} = err} -> {:ok, {:error, "invalid JSON: #{err.data}"}}
      {:error, reason} -> {:ok, {:error, reason}}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-3xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-6">
        <h1 class="text-2xl font-semibold text-slate-950">Backup &amp; restore</h1>
        <p class="mt-1 text-sm text-slate-700">
          Export every bookmark you have saved (sites, tags, notes,
          favicons) as a single JSON file. Restore is idempotent: existing
          sites are left alone but their tags get merged with the dump.
        </p>
      </div>

      <div class="mb-8 rounded-lg border border-slate-400 bg-slate-100 p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-slate-950">Export</h2>
        <p class="mt-1 text-sm text-slate-700">Downloads a JSON file scoped to your account.</p>
        <div class="mt-4">
          <a
            href={~p"/backup/export"}
            class="inline-block rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700"
          >
            Download backup
          </a>
        </div>
      </div>

      <div class="rounded-lg border border-slate-400 bg-slate-100 p-6 shadow-sm">
        <h2 class="text-lg font-semibold text-slate-950">Restore</h2>
        <p class="mt-1 text-sm text-slate-700">
          Upload a JSON backup. Re-running is safe.
        </p>

        <%= for entry <- @uploads.backup.entries do %>
          <div class="mt-3 text-sm text-slate-800">
            <%= entry.client_name %>
            <progress class="ml-2 align-middle" max="100" value={entry.progress} />
          </div>
        <% end %>

        <%= for {_ref, msg} <- @uploads.backup.errors do %>
          <div class="mt-3 text-sm text-red-700"><%= msg %></div>
        <% end %>

        <form
          id="restore-form"
          phx-submit="restore"
          phx-change="validate"
          class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center"
        >
          <.live_file_input
            upload={@uploads.backup}
            class="block w-full text-sm text-slate-800 file:mr-4 file:rounded-md file:border-0 file:bg-slate-200 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-slate-700 hover:file:bg-slate-200"
          />
          <%= submit "Restore",
            class:
              "rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700" %>
        </form>

        <div :if={@last_restore} class="mt-4 text-sm text-slate-700">
          Last restore: {@last_restore.tags_created} new tags, {@last_restore.sites_created} new sites, {@last_restore.sites_skipped} already present.
        </div>
      </div>
    </section>
    """
  end
end
