defmodule Tsundoku.Crawl do
  @moduledoc """
  Controls and reports on the metadata crawler: the Oban `:metadata`
  queue that runs `Tsundoku.Workers.EnrichMetadata`.

  Settings live in the database so they survive a restart. Concurrency
  and the paused flag are pushed to the running Oban queue whenever they
  change and again at boot; the per-domain delay and request timeout are
  read by each job as it starts.

  Everything here is server-wide, not per user. Single-node only, like
  `Tsundoku.DomainMutex`.
  """

  import Ecto.Query
  require Logger

  alias Tsundoku.Bookmarks.Site
  alias Tsundoku.Crawl.Settings
  alias Tsundoku.Repo
  alias Tsundoku.Workers.EnrichMetadata

  @queue :metadata
  @pending_states ~w(available scheduled executing retryable)
  @insert_chunk 500

  # ---- Settings ----

  @doc """
  Returns the saved settings, or the defaults if none have been saved.
  The default concurrency is the `:metadata` queue limit from config, so
  a deployment's existing setting carries over until someone changes it.
  """
  def get_settings do
    Repo.one(Settings) || %Settings{concurrency: configured_concurrency()}
  end

  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  @doc """
  Saves settings and applies them to the running queue. Returns
  `{:ok, settings}` or `{:error, changeset}`.
  """
  def update_settings(attrs) do
    result =
      get_settings()
      |> Settings.changeset(attrs)
      |> Repo.insert_or_update()

    with {:ok, settings} <- result do
      apply_settings(settings)
      {:ok, settings}
    end
  end

  def pause, do: update_settings(%{paused: true})
  def resume, do: update_settings(%{paused: false})

  @doc """
  Pushes concurrency and the paused flag to the running queue. Oban
  delivers these as notifications, so they take effect a moment later.
  """
  def apply_settings(%Settings{} = settings \\ get_settings()) do
    Oban.scale_queue(oban(), queue: @queue, limit: settings.concurrency)

    if settings.paused do
      Oban.pause_queue(oban(), queue: @queue)
    else
      Oban.resume_queue(oban(), queue: @queue)
    end

    :ok
  end

  @doc """
  Applies saved settings at boot. Does nothing if none have been saved.

  The queue may not be listening for notifications yet when this runs,
  so it reapplies until the queue reports the saved values.
  """
  def apply_saved_settings(attempts \\ 20) do
    case Repo.one(Settings) do
      nil -> :ok
      settings -> apply_until_in_effect(settings, attempts)
    end
  rescue
    error ->
      Logger.warning("could not apply crawl settings: #{Exception.message(error)}")
      :error
  end

  defp apply_until_in_effect(_settings, 0) do
    Logger.warning("crawl settings were not picked up by the queue")
    :error
  end

  defp apply_until_in_effect(settings, attempts) do
    apply_settings(settings)
    Process.sleep(250)

    case queue_status() do
      %{limit: limit, paused: paused}
      when limit == settings.concurrency and paused == settings.paused ->
        :ok

      _ ->
        apply_until_in_effect(settings, attempts - 1)
    end
  end

  # ---- Status ----

  @doc """
  What the running queue reports: `%{paused, limit, running}`, where
  `running` is the number of jobs executing now. `nil` if the queue
  isn't running on this node.
  """
  def queue_status do
    case Oban.check_queue(oban(), queue: @queue) do
      %{paused: paused, limit: limit, running: running} ->
        %{paused: paused, limit: limit, running: length(running)}

      _ ->
        nil
    end
  end

  @doc """
  Counts describing how crawling is going:

    * `:total`, `:ok`, `:failed`, `:uncrawled` - bookmark counts
    * `:by_status` - `[{crawl_status, count}]` for crawled bookmarks,
      most common first
    * `:jobs` - `%{state => count}` for the crawl queue
    * `:pending` - jobs waiting or running
    * `:recent` - the ten most recently crawled bookmarks
  """
  def stats do
    by_status =
      from(s in Site,
        where: not is_nil(s.crawl_status),
        group_by: s.crawl_status,
        select: {s.crawl_status, count()},
        order_by: [desc: count(), asc: s.crawl_status]
      )
      |> Repo.all()

    uncrawled = Repo.aggregate(uncrawled_sites(), :count)
    ok = by_status |> List.keyfind("ok", 0, {"ok", 0}) |> elem(1)
    crawled = by_status |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    jobs =
      from(j in Oban.Job,
        where: j.queue == ^to_string(@queue),
        group_by: j.state,
        select: {j.state, count()}
      )
      |> Repo.all()
      |> Map.new()

    recent =
      from(s in Site,
        where: not is_nil(s.crawled_at),
        order_by: [desc: s.crawled_at],
        limit: 10,
        select: map(s, [:id, :url, :display_name, :crawl_status, :crawled_at])
      )
      |> Repo.all()

    %{
      total: crawled + uncrawled,
      ok: ok,
      failed: crawled - ok,
      uncrawled: uncrawled,
      by_status: by_status,
      jobs: jobs,
      pending: jobs |> Map.take(@pending_states) |> Map.values() |> Enum.sum(),
      recent: recent
    }
  end

  # ---- Kicking off crawls ----

  @doc """
  Queues a crawl for every bookmark in `scope` that doesn't already have
  one waiting, and returns how many were queued.

    * `:uncrawled` - bookmarks that have never been crawled
    * `:failed` - bookmarks whose last crawl wasn't `ok`
    * `:all` - every bookmark
  """
  def enqueue(scope) when scope in [:uncrawled, :failed, :all] do
    pending =
      from(j in Oban.Job,
        where: j.queue == ^to_string(@queue) and j.state in ^@pending_states,
        select: fragment("?->>'site_id'", j.args)
      )

    ids =
      from(s in scoped_sites(scope),
        where: fragment("?::text", s.id) not in subquery(pending),
        select: s.id
      )
      |> Repo.all()

    ids
    |> Enum.chunk_every(@insert_chunk)
    |> Enum.each(fn chunk ->
      Oban.insert_all(oban(), Enum.map(chunk, &EnrichMetadata.new(%{site_id: &1})))
    end)

    length(ids)
  end

  defp scoped_sites(:all), do: Site
  defp scoped_sites(:uncrawled), do: uncrawled_sites()

  defp scoped_sites(:failed) do
    from s in Site, where: not is_nil(s.crawl_status) and s.crawl_status != "ok"
  end

  defp uncrawled_sites, do: from(s in Site, where: is_nil(s.crawl_status))

  defp configured_concurrency do
    :tsundoku
    |> Application.get_env(Oban, [])
    |> Keyword.get(:queues, [])
    |> Keyword.get(@queue, %Settings{}.concurrency)
  end

  # The Oban instance to control. Tests point this at an instance with
  # live queues; everywhere else it's the default.
  defp oban, do: Application.get_env(:tsundoku, :crawl_oban, Oban)
end
