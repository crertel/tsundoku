defmodule BookmarkServerWeb.ApiTestTest do
  use BookmarkServerWeb.ConnCase, async: true

  import BookmarkServer.AccountsFixtures
  alias BookmarkServer.Accounts

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, BookmarkServerWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    %{user: user, conn: conn, token: token}
  end

  describe "get tag" do
    test "fails without token", %{conn: conn} do
      path = Routes.api_path(conn, :test)
      conn = conn |> get( path)
      assert conn.status == 403
      assert conn.halted
    end

    test "succeeds with correct token and good params", %{conn: conn, token: token} do
      path = Routes.api_path(conn, :test)

      conn = conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> get( path )

      assert conn.resp_body == "{}"
      assert conn.status == 200
    end
  end
end
