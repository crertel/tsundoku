defmodule BookmarkServerWeb.Plugs.TokenAccessPlugTest do
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

  describe "test plug behavior" do
    test "missing bearer token results in 403", %{conn: conn} do
      conn = conn |> BookmarkServerWeb.Plugs.TokenAccess.call(%{})
      assert conn.status == 403
      assert conn.halted
    end

    test "incorrect bearer token results in 403", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "baconbaconbacon")
        |> BookmarkServerWeb.Plugs.TokenAccess.call(%{})

      assert conn.status == 403
      assert conn.halted
    end

    test "valid token results in success", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> BookmarkServerWeb.Plugs.TokenAccess.call(%{})

      refute conn.halted
    end
  end
end
