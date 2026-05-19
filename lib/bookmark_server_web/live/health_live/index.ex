defmodule BookmarkServerWeb.HealthLive.Index do
  use BookmarkServerWeb, :live_view

  alias BookmarkServer.Repo
  alias BookmarkServerWeb.Presence

  @poll_ms 5_000

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: :timer.send_interval(@poll_ms, :tick)

    {:ok,
     assign_defaults(session, socket)
     |> assign(page_title: "Health")
     |> assign_metrics()}
  end

  @impl true
  def handle_info(:tick, socket), do: {:noreply, assign_metrics(socket)}

  defp assign_metrics(socket) do
    assign(socket,
      db_latency_ms: db_latency_ms(),
      oban_counts: oban_counts(),
      memory_mb: :erlang.memory(:total) |> bytes_to_mb(),
      processes: :erlang.system_info(:process_count),
      node_uptime: node_uptime_string(),
      online_users: online_user_count(),
      sampled_at: DateTime.utc_now()
    )
  end

  defp db_latency_ms do
    {us, _} = :timer.tc(fn -> Repo.query!("SELECT 1") end)
    Float.round(us / 1000, 2)
  rescue
    _ -> nil
  end

  defp oban_counts do
    import Ecto.Query

    from(j in "oban_jobs",
      group_by: j.state,
      select: {j.state, count(j.id)}
    )
    |> Repo.all()
    |> Map.new()
  rescue
    _ -> %{}
  end

  defp online_user_count do
    Presence.list("users:online") |> map_size()
  end

  defp bytes_to_mb(bytes), do: Float.round(bytes / 1_048_576, 1)

  defp node_uptime_string do
    {ms, _} = :erlang.statistics(:wall_clock)
    seconds = div(ms, 1000)
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)
    "#{days}d #{hours}h #{minutes}m #{secs}s"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
      <div class="mb-6 flex items-baseline justify-between">
        <h1 class="text-2xl font-semibold text-slate-950">Health</h1>
        <p class="text-xs text-slate-500">
          Sampled {Calendar.strftime(@sampled_at, "%H:%M:%S UTC")}, refreshes every 5s
        </p>
      </div>

      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <.tile label="DB latency">
          <span class={if @db_latency_ms == nil, do: "text-red-700", else: ""}>
            {@db_latency_ms || "unreachable"}{if @db_latency_ms, do: " ms"}
          </span>
        </.tile>

        <.tile label="Online users">{@online_users}</.tile>

        <.tile label="BEAM memory">{@memory_mb} MB</.tile>

        <.tile label="Processes">{@processes}</.tile>

        <.tile label="Node uptime">{@node_uptime}</.tile>
      </div>

      <h2 class="mt-8 mb-3 text-lg font-semibold text-slate-950">Oban jobs</h2>
      <div class="rounded-lg border border-slate-400 bg-slate-100 p-4 shadow-sm">
        <%= if @oban_counts == %{} do %>
          <p class="text-sm text-slate-700">No jobs in the queue.</p>
        <% else %>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-slate-700">
                <th class="py-1 font-medium">State</th>
                <th class="py-1 font-medium">Count</th>
              </tr>
            </thead>
            <tbody>
              <%= for {state, count} <- Enum.sort_by(@oban_counts, &elem(&1, 0)) do %>
                <tr class="border-t border-slate-300">
                  <td class="py-1 text-slate-900">{state}</td>
                  <td class="py-1 font-mono text-slate-900">{count}</td>
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
