defmodule Mix.Tasks.Bookmarks.Export do
  @moduledoc """
  Dumps one user's bookmarks to a JSON file.

      mix bookmarks.export user@example.com path/to/backup.json

  If the output path is omitted, defaults to `bookmark-server-backup-<date>.json`
  in the current directory.
  """
  @shortdoc "Export one user's bookmarks to JSON"
  use Mix.Task

  @impl Mix.Task
  def run([email | rest]) do
    Mix.Task.run("app.start")

    user = BookmarkServer.Accounts.get_user_by_email(email)

    if is_nil(user) do
      Mix.raise("No user with email #{inspect(email)}")
    end

    path =
      case rest do
        [p | _] -> p
        [] -> "bookmark-server-backup-#{Date.utc_today() |> Date.to_iso8601()}.json"
      end

    body = user |> BookmarkServer.Bookmarks.export_user() |> Jason.encode!()
    File.write!(path, body)
    Mix.shell().info("Wrote #{byte_size(body)} bytes to #{path}")
  end

  def run(_) do
    Mix.raise("Usage: mix bookmarks.export <email> [output_path]")
  end
end
