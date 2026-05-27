defmodule Tsundoku.Workers.EnrichMetadata do
  @moduledoc """
  Background job: fetches a site's page, extracts metadata, updates the
  row. Args are `%{"site_id" => uuid}` so jobs survive serialization to
  the Postgres queue and pick up the latest site state on execution.

  Coordinates with `Tsundoku.DomainMutex` so two workers never
  hit the same host concurrently regardless of queue concurrency.
  Jobs that find the domain busy snooze and retry.
  """

  use Oban.Worker, queue: :metadata, max_attempts: 3

  alias Tsundoku.Bookmarks.Site
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
        case DomainMutex.try_acquire(site.domain) do
          :ok ->
            try do
              Metadata.enrich(Repo.preload(site, :tags))
              :ok
            after
              DomainMutex.release(site.domain)
            end

          :busy ->
            {:snooze, @snooze_seconds}
        end
    end
  end
end
