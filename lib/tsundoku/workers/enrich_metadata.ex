defmodule Tsundoku.Workers.EnrichMetadata do
  @moduledoc """
  Background job: fetches a site's page, extracts metadata, updates the
  row. Args are `%{"site_id" => uuid}` so jobs survive serialization to
  the Postgres queue and pick up the latest site state on execution.

  Coordinates with `Tsundoku.DomainMutex` so two workers never
  hit the same host concurrently regardless of queue concurrency, and
  leaves each host alone for the configured delay after a fetch.
  Jobs that find the domain busy snooze and retry.

  The delay and request timeout come from `Tsundoku.Crawl` settings,
  read as each job starts.
  """

  use Oban.Worker, queue: :metadata, max_attempts: 3

  alias Tsundoku.Bookmarks.Site
  alias Tsundoku.Crawl
  alias Tsundoku.DomainMutex
  alias Tsundoku.Metadata
  alias Tsundoku.Repo

  @snooze_seconds 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"site_id" => site_id}}) do
    case Repo.get(Site, site_id) do
      nil ->
        :ok

      site ->
        settings = Crawl.get_settings()

        case DomainMutex.try_acquire(site.domain) do
          :ok ->
            try do
              Metadata.enrich(Repo.preload(site, :tags), timeout: settings.timeout_ms)
              :ok
            after
              DomainMutex.release(site.domain, settings.delay_ms)
            end

          :busy ->
            {:snooze, snooze_seconds(settings.delay_ms)}
        end
    end
  end

  # Don't come back before the domain's cooldown could have ended.
  defp snooze_seconds(delay_ms), do: max(@snooze_seconds, ceil(delay_ms / 1_000))
end
