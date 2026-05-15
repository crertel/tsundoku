defmodule Mix.Tasks.Extension.Build do
  @moduledoc """
  Bundles the browser extension under `extension/` into
  `priv/static/extension/bookmark-server.zip` and `bookmark-server.xpi`
  (identical content, two extensions so the static plug can serve them
  with the right `Content-Type` for each browser).

  Run after editing files under `extension/`:

      mix extension.build
  """
  use Mix.Task

  @shortdoc "Builds the browser extension into priv/static/extension/"

  @source "extension"
  @dest "priv/static/extension"
  @basename "bookmark-server"

  def run(_args) do
    source = Path.expand(@source)
    dest = Path.expand(@dest)

    unless File.dir?(source) do
      Mix.raise("Extension source directory not found: #{source}")
    end

    File.mkdir_p!(dest)
    files = collect_files(source)

    zip_path = Path.join(dest, "#{@basename}.zip")
    xpi_path = Path.join(dest, "#{@basename}.xpi")

    entries =
      Enum.map(files, fn rel ->
        full = Path.join(source, rel)
        {String.to_charlist(rel), File.read!(full)}
      end)

    {:ok, _} = :zip.create(String.to_charlist(zip_path), entries)
    File.cp!(zip_path, xpi_path)

    rel = Path.relative_to_cwd(dest)
    Mix.shell().info("Built #{rel}/#{@basename}.zip and #{rel}/#{@basename}.xpi")
    Mix.shell().info("Bundled #{length(files)} files.")
  end

  defp collect_files(source) do
    source
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, source))
    |> Enum.sort()
  end
end
