defmodule Mix.Tasks.Oban.Empty do
  @moduledoc """
  Cancels all pending Oban jobs in a queue: available, scheduled, and
  retryable rows. Running jobs are not interrupted (Oban can't kill
  them mid-execution).

      mix oban.empty                  # default queue: metadata
      mix oban.empty --queue mywork
      mix oban.empty --delete         # also delete cancelled/discarded rows

  The Oban Web dashboard at /admin/oban gives the same kind of control
  per-job; this task is for the "purge everything pending" case where
  clicking around in the UI is too tedious.
  """
  use Mix.Task

  import Ecto.Query

  @shortdoc "Cancels all pending jobs in an Oban queue"

  @cancellable_states ~w(available scheduled retryable)
  @cancelled_states ~w(cancelled discarded)

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [queue: :string, delete: :boolean])

    queue = Keyword.get(opts, :queue, "metadata")
    delete? = Keyword.get(opts, :delete, false)

    Mix.Task.run("app.start")

    cancel_query =
      from j in Oban.Job,
        where: j.queue == ^queue and j.state in ^@cancellable_states

    {cancelled, _} = Oban.cancel_all_jobs(cancel_query)
    Mix.shell().info("Cancelled #{cancelled} pending #{queue} job(s).")

    if delete? do
      delete_query =
        from j in Oban.Job,
          where: j.queue == ^queue and j.state in ^@cancelled_states

      {deleted, _} = Oban.delete_all_jobs(delete_query)
      Mix.shell().info("Deleted #{deleted} cancelled/discarded #{queue} row(s).")
    end
  end
end
