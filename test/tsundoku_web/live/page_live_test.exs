defmodule TsundokuWeb.PageLiveTest do
  use TsundokuWeb.ConnCase

  import Phoenix.LiveViewTest

  test "disconnected and connected render", %{conn: conn} do
    {:ok, page_live, disconnected_html} = live(conn, "/")
    assert disconnected_html =~ "Tsundoku"
    assert render(page_live) =~ "Tsundoku"
  end
end
