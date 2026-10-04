defmodule TsundokuWeb.CrawlLive.Index do
  use TsundokuWeb, :live_view

  alias Tsundoku.Crawl

  @refresh_ms 3_000
  @job_states ~w(available scheduled executing retryable completed discarded cancelled)

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, :refresh)

    settings = Crawl.get_settings()

    {:ok,
     assign_defaults(session, socket)
     |> assign(page_title: "Crawler", job_states: @job_states)
     |> assign_settings(settings)
     |> assign_status()}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, assign_status(socket)}

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, assign_status(socket)}

  def handle_event("validate", %{"settings" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> Crawl.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Crawl.update_settings(params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> put_flash(:info, "Crawl settings saved.")
         |> assign_settings(settings)
         |> assign_status()}

      {:error, changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  def handle_event("pause", _params, socket) do
    {:ok, settings} = Crawl.pause()

    {:noreply,
     socket
     |> put_flash(:info, "Crawling paused.")
     |> assign_settings(settings)
     |> assign_status()}
  end

  def handle_event("resume", _params, socket) do
    {:ok, settings} = Crawl.resume()

    {:noreply,
     socket
     |> put_flash(:info, "Crawling resumed.")
     |> assign_settings(settings)
     |> assign_status()}
  end

  def handle_event("enqueue", %{"scope" => scope}, socket)
      when scope in ~w(uncrawled failed all) do
    count = Crawl.enqueue(String.to_existing_atom(scope))

    message =
      case count do
        0 -> "Nothing to queue: those bookmarks are crawled or already waiting."
        1 -> "Queued 1 crawl."
        n -> "Queued #{n} crawls."
      end

    {:noreply, socket |> put_flash(:info, message) |> assign_status()}
  end

  defp assign_settings(socket, settings) do
    assign(socket, settings: settings, changeset: Crawl.change_settings(settings))
  end

  defp assign_status(socket) do
    assign(socket,
      stats: Crawl.stats(),
      queue: Crawl.queue_status(),
      sampled_at: DateTime.utc_now()
    )
  end

  # The saved flag is the source of truth; the queue itself catches up a
  # moment after a change.
  defp queue_state(%{paused: true}, _queue), do: "Paused"
  defp queue_state(_settings, nil), do: "Not running"
  defp queue_state(_settings, _queue), do: "Running"

  defp percent(_part, 0), do: 0
  defp percent(part, total), do: round(part / total * 100)

  defp recent_title(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp recent_title(%{url: url}), do: url

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-6 flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <h1 class="text-2xl font-semibold text-slate-950">Crawler</h1>
          <p class="mt-1 text-sm text-slate-700">
            Fetches each bookmark's title, description and favicon. These settings apply to the whole server.
          </p>
        </div>
        <p class="text-xs text-slate-500">
          Sampled {Calendar.strftime(@sampled_at, "%H:%M:%S UTC")}, refreshes every 3s
        </p>
      </div>

      <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <.tile label="Queue">
          <span id="queue-state">{queue_state(@settings, @queue)}</span>
        </.tile>
        <.tile label="Fetching now">
          {if @queue, do: @queue.running, else: 0} / {if @queue,
            do: @queue.limit,
            else: @settings.concurrency}
        </.tile>
        <.tile label="Waiting"><span id="pending-count">{@stats.pending}</span></.tile>
        <.tile label="Crawled">
          {@stats.total - @stats.uncrawled} / {@stats.total}
          <span class="text-sm text-slate-600">
            ({percent(@stats.total - @stats.uncrawled, @stats.total)}%)
          </span>
        </.tile>
      </div>

      <div class="mt-6 rounded-lg border border-slate-400 bg-slate-100 p-4 shadow-sm">
        <h2 class="text-lg font-semibold text-slate-950">Controls</h2>
        <div class="mt-3 flex flex-wrap gap-2">
          <button
            :if={!@settings.paused}
            type="button"
            phx-click="pause"
            class="rounded-md border border-slate-400 bg-slate-50 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200"
          >
            Pause
          </button>
          <button
            :if={@settings.paused}
            type="button"
            phx-click="resume"
            class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700"
          >
            Resume
          </button>
          <button
            type="button"
            phx-click="enqueue"
            phx-value-scope="uncrawled"
            disabled={@stats.uncrawled == 0}
            class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Crawl {@stats.uncrawled} never crawled
          </button>
          <button
            type="button"
            phx-click="enqueue"
            phx-value-scope="failed"
            disabled={@stats.failed == 0}
            class="rounded-md border border-slate-400 bg-slate-50 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Retry {@stats.failed} failed
          </button>
          <button
            type="button"
            phx-click="enqueue"
            phx-value-scope="all"
            disabled={@stats.total == 0}
            data-confirm={"Re-crawl all #{@stats.total} bookmarks?"}
            class="rounded-md border border-slate-400 bg-slate-50 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Re-crawl all {@stats.total}
          </button>
          <button
            type="button"
            phx-click="refresh"
            class="rounded-md border border-slate-400 bg-slate-50 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200"
          >
            Refresh
          </button>
        </div>
        <p :if={@settings.paused and @stats.pending > 0} class="mt-3 text-sm text-slate-700">
          {@stats.pending} crawls are waiting and will start when you resume.
        </p>
      </div>

      <div class="mt-6 rounded-lg border border-slate-400 bg-slate-100 p-4 shadow-sm">
        <h2 class="text-lg font-semibold text-slate-950">Settings</h2>

        <.form
          :let={f}
          for={@changeset}
          id="crawl-settings-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-3 grid gap-4 sm:grid-cols-3"
        >
          <div>
            <%= label f, :concurrency, class: "block text-sm font-medium text-slate-700" do %>
              Pages at once
            <% end %>
            <%= number_input f, :concurrency,
              min: 1,
              max: 20,
              class:
                "mt-1 block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200" %>
            <p class="mt-1 text-xs text-slate-500">1 to 20, across all domains.</p>
            <%= error_tag f, :concurrency %>
          </div>

          <div>
            <%= label f, :delay_ms, class: "block text-sm font-medium text-slate-700" do %>
              Delay per domain (ms)
            <% end %>
            <%= number_input f, :delay_ms,
              min: 0,
              max: 60_000,
              step: 100,
              class:
                "mt-1 block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200" %>
            <p class="mt-1 text-xs text-slate-500">
              Pause between two fetches from the same domain.
            </p>
            <%= error_tag f, :delay_ms %>
          </div>

          <div>
            <%= label f, :timeout_ms, class: "block text-sm font-medium text-slate-700" do %>
              Request timeout (ms)
            <% end %>
            <%= number_input f, :timeout_ms,
              min: 1_000,
              max: 60_000,
              step: 500,
              class:
                "mt-1 block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200" %>
            <p class="mt-1 text-xs text-slate-500">How long to wait for a page.</p>
            <%= error_tag f, :timeout_ms %>
          </div>

          <div class="sm:col-span-3">
            <%= submit "Save settings",
              phx_disable_with: "Saving...",
              class:
                "rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700" %>
          </div>
        </.form>
      </div>

      <div class="mt-6 grid gap-6 lg:grid-cols-2">
        <div class="rounded-lg border border-slate-400 bg-slate-100 p-4 shadow-sm">
          <h2 class="text-lg font-semibold text-slate-950">Bookmarks by crawl result</h2>
          <table id="crawl-results" class="mt-3 w-full text-sm">
            <tbody>
              <tr class="border-t border-slate-300">
                <td class="py-1 text-slate-900">
                  <.link navigate={~p"/sites?q=metadata:missing"} class="text-sky-700 hover:text-sky-900">
                    never crawled
                  </.link>
                </td>
                <td class="py-1 text-right font-mono text-slate-900">{@stats.uncrawled}</td>
              </tr>
              <%= for {status, count} <- @stats.by_status do %>
                <tr class="border-t border-slate-300">
                  <td class="py-1 text-slate-900">
                    <.link
                      navigate={~p"/sites?q=#{"status:" <> status}"}
                      class="text-sky-700 hover:text-sky-900"
                    >
                      {status}
                    </.link>
                  </td>
                  <td class="py-1 text-right font-mono text-slate-900">{count}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <p class="mt-3 text-xs text-slate-500">
            Counts cover every account. The links show your own bookmarks.
          </p>
        </div>

        <div class="rounded-lg border border-slate-400 bg-slate-100 p-4 shadow-sm">
          <h2 class="text-lg font-semibold text-slate-950">Crawl jobs</h2>
          <table id="crawl-jobs" class="mt-3 w-full text-sm">
            <tbody>
              <%= for state <- @job_states do %>
                <tr class="border-t border-slate-300">
                  <td class="py-1 text-slate-900">{state}</td>
                  <td class="py-1 text-right font-mono text-slate-900">
                    {Map.get(@stats.jobs, state, 0)}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <p class="mt-3 text-xs text-slate-500">
            "scheduled" jobs are waiting on a busy domain or a retry. Finished jobs are pruned after a while.
          </p>
        </div>
      </div>

      <div class="mt-6 rounded-lg border border-slate-400 bg-slate-100 p-4 shadow-sm">
        <h2 class="text-lg font-semibold text-slate-950">Recently crawled</h2>
        <%= if @stats.recent == [] do %>
          <p class="mt-3 text-sm text-slate-700">Nothing has been crawled yet.</p>
        <% else %>
          <table id="recent-crawls" class="mt-3 w-full text-sm">
            <tbody>
              <%= for site <- @stats.recent do %>
                <tr class="border-t border-slate-300">
                  <td class="max-w-0 truncate py-1 pr-3 text-slate-900">
                    <.link navigate={~p"/sites/#{site.id}"} class="text-sky-700 hover:text-sky-900">
                      {recent_title(site)}
                    </.link>
                  </td>
                  <td class="whitespace-nowrap py-1 pr-3 text-slate-900">{site.crawl_status}</td>
                  <td class="whitespace-nowrap py-1 text-right font-mono text-xs text-slate-600">
                    {Calendar.strftime(site.crawled_at, "%Y-%m-%d %H:%M:%S")}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp tile(assigns) do
    ~H"""
    <div class="rounded-lg border border-slate-400 bg-slate-100 p-4 shadow-sm">
      <div class="text-xs font-semibold uppercase tracking-wide text-slate-500">{@label}</div>
      <div class="mt-2 text-2xl font-mono text-slate-950">{render_slot(@inner_block)}</div>
    </div>
    """
  end
end
