defmodule TsundokuWeb.HealthLiveTest do
  use TsundokuWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Tsundoku.Bookmarks

  setup %{conn: conn} do
    user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
    %{conn: log_in_user(conn, user), user: user}
  end

  test "shows node and database metrics", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/health")

    assert html =~ "Health"
    assert html =~ "DB latency"
    assert html =~ ~r/[\d.]+ ms/
    refute html =~ "unreachable"
    assert html =~ "Online users"
    assert html =~ ~r/[\d.]+ MB/
    assert html =~ "Processes"
    assert html =~ ~r/\d+d \d+h \d+m \d+s/
    assert html =~ "No jobs in the queue."
  end

  test "counts Oban jobs by state", %{conn: conn, user: user} do
    # Saving a site enqueues a metadata job.
    for n <- 1..2 do
      {:ok, _} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/#{n}",
          "created_by_id" => user.id,
          "tags" => []
        })
    end

    {:ok, view, html} = live(conn, "/admin/health")

    refute html =~ "No jobs in the queue."
    assert view |> element("tbody tr", "available") |> render() =~ ~r/>\s*2\s*</
  end

  test "refreshes on tick", %{conn: conn, user: user} do
    {:ok, view, html} = live(conn, "/admin/health")
    assert html =~ "No jobs in the queue."

    {:ok, _} =
      Bookmarks.create_site(%{
        "url" => "https://example.com/later",
        "created_by_id" => user.id,
        "tags" => []
      })

    send(view.pid, :tick)

    assert has_element?(view, "tbody tr", "available")
  end

  test "requires logging in" do
    conn = build_conn()

    assert {:error, {:redirect, %{to: path}}} = live(conn, "/admin/health")
    assert path == Routes.user_session_path(conn, :new)
  end
end
