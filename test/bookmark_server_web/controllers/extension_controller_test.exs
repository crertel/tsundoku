defmodule BookmarkServerWeb.ExtensionControllerTest do
  use BookmarkServerWeb.ConnCase, async: true

  import BookmarkServer.AccountsFixtures

  describe "GET /extension" do
    test "redirects when signed out", %{conn: conn} do
      conn = get(conn, "/extension")
      assert redirected_to(conn) =~ "/users/log_in"
    end

    test "renders install instructions with a fresh token for the signed-in user",
         %{conn: conn} do
      user = user_fixture()
      conn = conn |> log_in_user(user) |> get("/extension")

      response = html_response(conn, 200)
      assert response =~ "Browser extension"
      assert response =~ "Server URL"
      assert response =~ "API token"
      assert response =~ ~r/[A-Za-z0-9+\/=]{32,}/
    end
  end
end
