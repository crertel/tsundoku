defmodule Mix.Tasks.Backfill.Metadata do
  @moduledoc """
  Enqueues an EnrichMetadata Oban job for every site that needs one.

  By default skips sites whose `crawled_at` is already set; pass
  `--force` to re-enrich everything. Scope to a single user with
  `--user-id <uuid>`.

      mix backfill.metadata
      mix backfill.metadata --force
      mix backfill.metadata --user-id <uuid>

  The actual fetching happens in Oban workers, so the task returns
  quickly once all jobs are inserted. Watch progress in the
  `oban_jobs` table or the logs.
  """
  use Mix.Task

  @shortdoc "Enqueues metadata enrichment for sites missing it"

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [force: :boolean, user_id: :string],
        aliases: [f: :force]
      )

    Mix.Task.run("app.start")

    count =
      Tsundoku.Bookmarks.enqueue_metadata_backfill(
        force: Keyword.get(opts, :force, false),
        user_id: opts[:user_id]
      )

    Mix.shell().info("Enqueued metadata enrichment for #{count} site(s).")
  end
end
