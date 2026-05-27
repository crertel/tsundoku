defmodule Mix.Tasks.Bookmarks.Restore do
  @moduledoc """
  Restores a JSON backup into one user's account. Idempotent.

      mix bookmarks.restore user@example.com path/to/backup.json
  """
  @shortdoc "Restore a JSON backup into one user's account"
  use Mix.Task

  @impl Mix.Task
  def run([email, path]) do
    Mix.Task.run("app.start")

    user = Tsundoku.Accounts.get_user_by_email(email)

    if is_nil(user) do
      Mix.raise("No user with email #{inspect(email)}")
    end

    dump = path |> File.read!() |> Jason.decode!()

    case Tsundoku.Bookmarks.restore_user(user, dump) do
      {:ok, summary} ->
        Mix.shell().info(
          "Restored: #{summary.tags_created} new tags, " <>
            "#{summary.sites_created} new sites, " <>
            "#{summary.sites_skipped} already-present sites (tags merged)."
        )

      {:error, reason} ->
        Mix.raise("Restore failed: #{inspect(reason)}")
    end
  end

  def run(_) do
    Mix.raise("Usage: mix bookmarks.restore <email> <input_path>")
  end
end
