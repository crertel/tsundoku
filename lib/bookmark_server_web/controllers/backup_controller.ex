defmodule BookmarkServerWeb.BackupController do
  use BookmarkServerWeb, :controller

  alias BookmarkServer.Bookmarks

  def export(conn, _params) do
    user = conn.assigns.current_user
    dump = Bookmarks.export_user(user)
    body = Jason.encode!(dump)

    filename =
      "bookmark-server-backup-#{Date.utc_today() |> Date.to_iso8601()}.json"

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, body)
  end
end
