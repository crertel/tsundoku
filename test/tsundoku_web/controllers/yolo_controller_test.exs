defmodule TsundokuWeb.YoloControllerTest do
  use TsundokuWeb.ConnCase, async: true

  import Tsundoku.AccountsFixtures
  alias Tsundoku.Bookmarks

  describe "GET /yolo" do
    setup :register_and_log_in_user

    test "redirects to one of the user's bookmarks", %{conn: conn, user: user} do
      other = user_fixture()

      {:ok, mine} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/mine",
          "created_by_id" => user.id,
          "tags" => []
        })

      for n <- 1..5 do
        {:ok, _} =
          Bookmarks.create_site(%{
            "url" => "https://example.com/theirs-#{n}",
            "created_by_id" => other.id,
            "tags" => []
          })
      end

      conn = get(conn, Routes.yolo_path(conn, :show))

      assert redirected_to(conn) == Routes.site_show_path(conn, :show, mine)
    end

    test "sends you to the sites page when there's nothing saved", %{conn: conn} do
      conn = get(conn, Routes.yolo_path(conn, :show))

      assert redirected_to(conn) == Routes.site_index_path(conn, :index)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "No bookmarks yet"
    end
  end

  test "GET /yolo requires logging in", %{conn: conn} do
    conn = get(conn, Routes.yolo_path(conn, :show))

    assert redirected_to(conn) == Routes.user_session_path(conn, :new)
  end
end
