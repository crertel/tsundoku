defmodule TsundokuWeb.ImportLiveTest do
  use TsundokuWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Tsundoku.Bookmarks

  @bookmarks_html """
  <!DOCTYPE NETSCAPE-Bookmark-file-1>
  <DL><p>
    <DT><H3>Reading</H3>
    <DL><p>
      <DT><A HREF="https://example.com/one">Page one</A>
      <DT><A HREF="https://example.com/two">Page two</A>
    </DL><p>
  </DL><p>
  """

  setup %{conn: conn} do
    user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
    %{conn: log_in_user(conn, user), user: user}
  end

  defp upload(view, name, content) do
    view
    |> file_input("#import-bookmark-form", :bookmark_import, [
      %{name: name, content: content, type: "text/html"}
    ])
    |> render_upload(name)
  end

  test "renders the upload form", %{conn: conn} do
    {:ok, view, html} = live(conn, "/import")

    assert html =~ "Import bookmarks"
    assert has_element?(view, "#import-bookmark-form")
  end

  test "imports an uploaded bookmarks file in the background", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, "/import")

    assert upload(view, "bookmarks.html", @bookmarks_html) =~ "bookmarks.html"

    html = view |> form("#import-bookmark-form") |> render_submit()

    assert html =~ "Importing 2 bookmarks in the background"
    assert html =~ "Queued: 0 / 2"
    assert Bookmarks.count_user_sites(user.id) == 0

    # Test config sets `Oban testing: :manual`, so drive the job to run.
    assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :import, with_safety: false)

    html = render(view)
    assert html =~ "Imported 2 new bookmarks and 1 new tags."
    assert has_element?(view, ~s(a[href="/sites"]), "View sites")
    refute html =~ "Queued:"

    assert Bookmarks.count_user_sites(user.id) == 2

    site =
      "https://example.com/one"
      |> Bookmarks.get_user_bookmark_by_url(user.id)
      |> Tsundoku.Repo.preload(:tags)

    assert site.display_name == "Page one"
    assert Enum.map(site.tags, & &1.name) == ["Reading"]
  end

  test "shows progress reported by the import job", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/import")
    upload(view, "bookmarks.html", @bookmarks_html)
    view |> form("#import-bookmark-form") |> render_submit()

    send(view.pid, {:import_progress, %{processed: 1, total: 2, stage: :sites}})

    assert render(view) =~ "Sites: 1 / 2"
  end

  test "says so when submitted without a file", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/import")

    assert view |> form("#import-bookmark-form") |> render_submit() =~ "No file was uploaded."
  end

  test "rejects a file that isn't html", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, "/import")

    input =
      file_input(view, "#import-bookmark-form", :bookmark_import, [
        %{name: "notes.txt", content: "hello", type: "text/plain"}
      ])

    assert {:error, [[_ref, :not_accepted]]} = render_upload(input, "notes.txt")
    assert render(view) =~ "That file type isn&#39;t accepted."

    assert view |> form("#import-bookmark-form") |> render_submit() =~
             "That file was rejected or is still uploading."

    assert Oban.drain_queue(queue: :import).success == 0
    assert Bookmarks.count_user_sites(user.id) == 0
  end
end
