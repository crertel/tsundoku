defmodule TsundokuWeb.CrawlLiveTest do
  use TsundokuWeb.ConnCase
  use Oban.Testing, repo: Tsundoku.Repo

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Tsundoku.Bookmarks
  alias Tsundoku.Bookmarks.Site
  alias Tsundoku.Crawl
  alias Tsundoku.Repo
  alias Tsundoku.Workers.EnrichMetadata

  setup %{conn: conn} do
    user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
    %{conn: log_in_user(conn, user), user: user}
  end

  # Saves a site, clears the crawl job that saving enqueues, and sets
  # its crawl status (nil = never crawled).
  defp site_fixture(user, name, status \\ nil) do
    {:ok, site} =
      Bookmarks.create_site(%{
        "url" => "https://example.com/#{name}",
        "display_name" => name,
        "created_by_id" => user.id,
        "tags" => []
      })

    Repo.delete_all(Oban.Job)

    if status do
      Repo.update_all(from(s in Site, where: s.id == ^site.id),
        set: [crawl_status: status, crawled_at: DateTime.utc_now()]
      )
    end

    site
  end

  defp cell(view, table, row_text) do
    view |> element("##{table} tr", row_text) |> render()
  end

  test "requires logging in" do
    conn = build_conn()

    assert {:error, {:redirect, %{to: path}}} = live(conn, "/admin/crawl")
    assert path == Routes.user_session_path(conn, :new)
  end

  test "is linked from the user menu", %{conn: conn} do
    assert conn |> get("/sites") |> html_response(200) =~ ~s(href="/admin/crawl")
  end

  describe "status" do
    test "shows an empty server", %{conn: conn} do
      {:ok, view, html} = live(conn, "/admin/crawl")

      assert html =~ "Crawler"
      assert view |> element("#queue-state") |> render() =~ "Not running"
      assert view |> element("#pending-count") |> render() =~ ">0<"
      assert html =~ "Nothing has been crawled yet."
      assert has_element?(view, ~s(button[phx-value-scope="uncrawled"][disabled]))
      assert has_element?(view, ~s(button[phx-value-scope="failed"][disabled]))
      assert has_element?(view, ~s(button[phx-value-scope="all"][disabled]))
    end

    test "shows crawl results, jobs, and recent crawls", %{conn: conn, user: user} do
      site_fixture(user, "never")
      site_fixture(user, "fine", "ok")
      gone = site_fixture(user, "gone", "http_404")

      {:ok, view, html} = live(conn, "/admin/crawl")

      assert html =~ "2 / 3"
      assert html =~ "(67%)"
      assert cell(view, "crawl-results", "never crawled") =~ ~r/>\s*1\s*</
      assert cell(view, "crawl-results", "http_404") =~ ~r/>\s*1\s*</
      assert has_element?(view, ~s(#crawl-results a[href="/sites?q=status%3Ahttp_404"]))
      assert has_element?(view, ~s(#recent-crawls a[href="/sites/#{gone.id}"]), "gone")
      refute has_element?(view, "#recent-crawls a", "never")

      assert has_element?(view, ~s(button[phx-value-scope="uncrawled"]), "Crawl 1 never crawled")
      assert has_element?(view, ~s(button[phx-value-scope="failed"]), "Retry 1 failed")
      assert has_element?(view, ~s(button[phx-value-scope="all"]), "Re-crawl all 3")
    end

    test "refreshes on the timer and on the Refresh button", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, "/admin/crawl")

      site_fixture(user, "later", "timeout")
      send(view.pid, :refresh)
      assert cell(view, "crawl-results", "timeout") =~ ~r/>\s*1\s*</

      site_fixture(user, "later-still", "timeout")
      view |> element("button", "Refresh") |> render_click()
      assert cell(view, "crawl-results", "timeout") =~ ~r/>\s*2\s*</
    end
  end

  describe "kicking off crawls" do
    test "queues never-crawled bookmarks", %{conn: conn, user: user} do
      never = site_fixture(user, "never")
      site_fixture(user, "fine", "ok")

      {:ok, view, _html} = live(conn, "/admin/crawl")

      html = view |> element(~s(button[phx-value-scope="uncrawled"])) |> render_click()

      assert html =~ "Queued 1 crawl."
      assert view |> element("#pending-count") |> render() =~ ">1<"
      assert cell(view, "crawl-jobs", "available") =~ ~r/>\s*1\s*</
      assert [%{args: %{"site_id" => id}}] = all_enqueued(worker: EnrichMetadata)
      assert id == never.id

      # A second click finds nothing new to queue.
      html = view |> element(~s(button[phx-value-scope="uncrawled"])) |> render_click()
      assert html =~ "Nothing to queue"
      assert length(all_enqueued(worker: EnrichMetadata)) == 1
    end

    test "retries failed bookmarks and re-crawls everything", %{conn: conn, user: user} do
      site_fixture(user, "never")
      site_fixture(user, "fine", "ok")
      site_fixture(user, "gone", "http_404")

      {:ok, view, _html} = live(conn, "/admin/crawl")

      assert view |> element(~s(button[phx-value-scope="failed"])) |> render_click() =~
               "Queued 1 crawl."

      assert view |> element(~s(button[phx-value-scope="all"])) |> render_click() =~
               "Queued 2 crawls."

      assert length(all_enqueued(worker: EnrichMetadata)) == 3
    end

    test "ignores an unknown scope", %{conn: conn, user: user} do
      site_fixture(user, "never")
      {:ok, view, _html} = live(conn, "/admin/crawl")

      Process.flag(:trap_exit, true)
      catch_exit(render_hook(view, "enqueue", %{"scope" => "everything"}))

      assert all_enqueued(worker: EnrichMetadata) == []
    end
  end

  describe "pause and resume" do
    test "toggles the saved flag and the button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/crawl")

      html = view |> element("button", "Pause") |> render_click()

      assert html =~ "Crawling paused."
      assert view |> element("#queue-state") |> render() =~ "Paused"
      assert Crawl.get_settings().paused
      refute has_element?(view, "button", "Pause")

      html = view |> element("button", "Resume") |> render_click()

      assert html =~ "Crawling resumed."
      refute Crawl.get_settings().paused
      assert has_element?(view, "button", "Pause")
    end

    test "says how many crawls are waiting while paused", %{conn: conn, user: user} do
      site_fixture(user, "never")
      {:ok, _} = Crawl.pause()

      {:ok, view, _html} = live(conn, "/admin/crawl")
      html = view |> element(~s(button[phx-value-scope="uncrawled"])) |> render_click()

      assert html =~ "1 crawls are waiting and will start when you resume."
    end
  end

  describe "settings form" do
    test "shows the current settings", %{conn: conn} do
      {:ok, _} = Crawl.update_settings(%{concurrency: 3, delay_ms: 2_500, timeout_ms: 8_000})

      {:ok, view, _html} = live(conn, "/admin/crawl")
      form = view |> element("#crawl-settings-form") |> render()

      assert form =~ ~s(value="3")
      assert form =~ ~s(value="2500")
      assert form =~ ~s(value="8000")
    end

    test "saves valid settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/crawl")

      html =
        view
        |> form("#crawl-settings-form",
          settings: %{concurrency: 2, delay_ms: 500, timeout_ms: 5_000}
        )
        |> render_submit()

      assert html =~ "Crawl settings saved."
      assert %{concurrency: 2, delay_ms: 500, timeout_ms: 5_000} = Crawl.get_settings()
      assert html =~ "0 / 2"
    end

    test "shows validation errors and saves nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/crawl")

      html =
        view
        |> form("#crawl-settings-form", settings: %{concurrency: 0})
        |> render_change()

      assert html =~ "must be greater than or equal to 1"

      html =
        view
        |> form("#crawl-settings-form",
          settings: %{concurrency: 50, delay_ms: -5, timeout_ms: 10}
        )
        |> render_submit()

      assert html =~ "must be less than or equal to 20"
      assert html =~ "must be greater than or equal to 0"
      assert html =~ "must be greater than or equal to 1000"
      assert Repo.aggregate(Crawl.Settings, :count) == 0
    end

    test "saving settings keeps the paused flag", %{conn: conn} do
      {:ok, _} = Crawl.pause()
      {:ok, view, _html} = live(conn, "/admin/crawl")

      view |> form("#crawl-settings-form", settings: %{concurrency: 4}) |> render_submit()

      assert %{concurrency: 4, paused: true} = Crawl.get_settings()
    end
  end
end
