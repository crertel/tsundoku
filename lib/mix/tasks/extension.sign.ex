defmodule Mix.Tasks.Extension.Sign do
  @moduledoc """
  Submits the bundled browser extension to Mozilla AMO for signing
  via `web-ext sign --channel=unlisted` and stashes the signed XPI at
  `extension/dist/tsundoku.xpi`.

  `mix extension.build` overlays that file onto
  `priv/static/extension/tsundoku.xpi` when present, so subsequent
  builds (including the nix release) ship the signed artifact.

  Requires:

      AMO_JWT_ISSUER     # JWT issuer from addons.mozilla.org API key page
      AMO_JWT_SECRET     # JWT secret from the same page

  `--channel=unlisted` means Mozilla signs but does not list the
  extension in the public AMO catalog. Stable Firefox will still
  install it via the served XPI link.

  This task does not bump the version. Edit
  `extension/manifest.json` first; AMO refuses to sign two builds at
  the same version.
  """
  use Mix.Task

  @shortdoc "Submits extension to Mozilla AMO and stores the signed XPI."

  @source "extension"
  @dist "extension/dist"
  @basename "tsundoku"

  def run(_args) do
    issuer = System.get_env("AMO_JWT_ISSUER") |> presence()
    secret = System.get_env("AMO_JWT_SECRET") |> presence()

    if is_nil(issuer) or is_nil(secret) do
      Mix.raise("""
      AMO_JWT_ISSUER and AMO_JWT_SECRET must be set. Get them from
      https://addons.mozilla.org/developers/addon/api/key/
      """)
    end

    unless System.find_executable("web-ext") do
      Mix.raise("""
      `web-ext` not found on PATH. Run inside `nix develop` or install
      it: https://extensionworkshop.com/documentation/develop/web-ext-command-reference/
      """)
    end

    Mix.Task.run("extension.build", [])

    File.mkdir_p!(@dist)

    artifacts_dir =
      Path.join(System.tmp_dir!(), "tsundoku-sign-#{System.unique_integer([:positive])}")

    File.mkdir_p!(artifacts_dir)

    args = [
      "sign",
      "--channel=unlisted",
      "--source-dir=#{@source}",
      "--api-key=#{issuer}",
      "--api-secret=#{secret}",
      "--artifacts-dir=#{artifacts_dir}"
    ]

    Mix.shell().info("web-ext sign --channel=unlisted (this can take a minute)…")

    case System.cmd("web-ext", args, stderr_to_stdout: true) do
      {output, 0} ->
        Mix.shell().info(output)
        signed = locate_signed!(artifacts_dir)
        dest = Path.join(@dist, "#{@basename}.xpi")
        File.cp!(signed, dest)
        File.rm_rf!(artifacts_dir)
        Mix.shell().info("Signed XPI written to #{dest}")
        Mix.shell().info("Re-run `mix extension.build` to overlay it onto priv/static.")

      {output, exit_code} ->
        Mix.shell().error(output)
        File.rm_rf!(artifacts_dir)
        Mix.raise("web-ext sign failed (exit #{exit_code}).")
    end
  end

  defp locate_signed!(dir) do
    case Path.wildcard(Path.join(dir, "*.xpi")) do
      [xpi] ->
        xpi

      [] ->
        Mix.raise("web-ext reported success but no XPI was written to #{dir}.")

      many ->
        Mix.raise("web-ext produced multiple XPIs (#{Enum.join(many, ", ")}); expected one.")
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(s), do: s
end
