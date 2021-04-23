defmodule BookmarkServerWeb.Helpers do
  def grab_user_info(conn) do
    %{"current_user" => conn.assigns.current_user}
  end
end
