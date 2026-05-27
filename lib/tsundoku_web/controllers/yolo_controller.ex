defmodule TsundokuWeb.YoloController do
  use TsundokuWeb, :controller

  alias Tsundoku.Bookmarks

  def show(conn, _params) do
    user = conn.assigns.current_user

    case Bookmarks.random_user_site(user.id) do
      nil ->
        conn
        |> put_flash(:info, "No bookmarks yet — save something to YOLO!")
        |> redirect(to: ~p"/sites")

      site ->
        redirect(conn, to: ~p"/sites/#{site.id}")
    end
  end
end
