defmodule TsundokuWeb.BackupLiveTest do
  use TsundokuWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Tsundoku.Bookmarks

  setup %{conn: conn} do
    user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
    %{conn: log_in_user(conn, user), user: user}
  end

  # A JSON backup of another account holding one tagged site.
  defp backup_json do
    source = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
    {:ok, tag} = Bookmarks.create_tag(%{name: "elixir", created_by_id: source.id})

    {:ok, _} =
      Bookmarks.create_site(%{
        "url" => "https://example.com/backed-up",
        "display_name" => "Backed up",
        "created_by_id" => source.id,
        "tags" => [tag]
      })

    source |> Bookmarks.export_user() |> Jason.encode!()
  end

  defp restore(view, content) do
    view
    |> file_input("#restore-form", :backup, [
      %{name: "backup.json", content: content, type: "application/json"}
    ])
    |> render_upload("backup.json")

    view |> form("#restore-form") |> render_submit()
  end

  describe "BackupLive" do
    test "links to the export download", %{conn: conn} do
      {:ok, view, html} = live(conn, "/backup")

      assert html =~ "Backup &amp; restore"
      assert has_element?(view, ~s(a[href="/backup/export"]), "Download backup")
    end

    test "restores an uploaded backup", %{conn: conn, user: user} do
      json = backup_json()
      {:ok, view, _html} = live(conn, "/backup")

      html = restore(view, json)

      assert html =~ "Restored: 1 new tags, 1 new sites, 0 already-present sites"
      assert html =~ "Last restore: 1 new tags, 1 new sites, 0 already present."

      site =
        "https://example.com/backed-up"
        |> Bookmarks.get_user_bookmark_by_url(user.id)
        |> Tsundoku.Repo.preload(:tags)

      assert site.display_name == "Backed up"
      assert Enum.map(site.tags, & &1.name) == ["elixir"]
    end

    test "restoring the same backup twice skips what's already there", %{conn: conn, user: user} do
      json = backup_json()
      {:ok, view, _html} = live(conn, "/backup")

      restore(view, json)
      html = restore(view, json)

      assert html =~ "Restored: 0 new tags, 0 new sites, 1 already-present sites"
      assert Bookmarks.count_user_sites(user.id) == 1
    end

    test "reports invalid JSON", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, "/backup")

      html = restore(view, "{not json")

      assert html =~ "Restore failed"
      assert html =~ "invalid JSON"
      assert Bookmarks.count_user_sites(user.id) == 0
    end

    test "reports an unsupported backup version", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/backup")

      html = restore(view, Jason.encode!(%{version: 99, sites: []}))

      assert html =~ "Restore failed"
      assert html =~ "unsupported_version"
    end

    test "says so when submitted without a file", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/backup")

      assert view |> form("#restore-form") |> render_submit() =~ "No file was uploaded."
    end
  end

  describe "GET /backup/export" do
    test "downloads the user's data as a JSON attachment", %{conn: conn, user: user} do
      {:ok, _} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/mine",
          "display_name" => "Mine",
          "created_by_id" => user.id,
          "tags" => []
        })

      conn = get(conn, "/backup/export")

      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ~r/^attachment; filename="tsundoku-backup-\d{4}-\d{2}-\d{2}\.json"$/

      dump = json_response(conn, 200)
      assert dump["version"] == 1
      assert dump["user_email"] == user.email
      assert [%{"url" => "https://example.com/mine", "display_name" => "Mine"}] = dump["sites"]
    end

    test "requires logging in" do
      conn = get(build_conn(), "/backup/export")

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end
  end
end
