defmodule Tsundoku.Workers.ImportBookmarks do
  @moduledoc """
  Background job for bulk bookmark imports.

  Args (from `ApiController.import_bookmarks` / `ImportLive.Index`):

      %{
        "user_id" => "uuid",
        "tags"    => ["tag-a", "tag-b", ...],
        "urls"    => [%{"tags" => [...], "url" => "...", "title" => "..."}, ...]
      }

  Per batch, broadcasts `{:import_progress, %{processed, total, stage}}`
  on the `"imports:job:<job_id>"` PubSub topic and stamps the same
  numbers onto the Oban job's `meta` field so the `/api/import_status/:id`
  endpoint can read progress without a live subscriber.
  """

  use Oban.Worker, queue: :import, max_attempts: 1

  alias Tsundoku.Bookmarks
  alias Tsundoku.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{"user_id" => user_id, "tags" => tags, "urls" => urls}
      }) do
    total = length(urls)
    topic = "imports:job:#{job_id}"

    stamp_meta(job_id, %{"processed" => 0, "total" => total, "stage" => "starting"})

    progress = fn %{processed: processed, stage: stage} ->
      Phoenix.PubSub.broadcast(
        Tsundoku.PubSub,
        topic,
        {:import_progress, %{processed: processed, total: total, stage: stage}}
      )

      stamp_meta(job_id, %{
        "processed" => processed,
        "total" => total,
        "stage" => Atom.to_string(stage)
      })
    end

    result = Bookmarks.bulk_insert_imported(tags, urls, user_id, progress)

    Phoenix.PubSub.broadcast(
      Tsundoku.PubSub,
      topic,
      {:import_complete, result}
    )

    stamp_meta(job_id, %{
      "processed" => total,
      "total" => total,
      "stage" => "complete",
      "sites_inserted" => result.sites_inserted,
      "tags_inserted" => result.tags_inserted
    })

    :ok
  end

  defp stamp_meta(job_id, meta) do
    import Ecto.Query

    from(j in Oban.Job, where: j.id == ^job_id)
    |> Repo.update_all(set: [meta: meta])

    :ok
  end
end
