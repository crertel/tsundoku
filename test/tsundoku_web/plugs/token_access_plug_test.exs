defmodule TsundokuWeb.Plugs.TokenAccessPlugTest do
  use TsundokuWeb.ConnCase, async: true
  import Tsundoku.AccountsFixtures
  alias Tsundoku.Accounts

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, TsundokuWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    %{user: user, conn: conn, token: token}
  end

  describe "test plug behavior" do
    test "missing bearer token results in 403", %{conn: conn} do
      conn = conn |> TsundokuWeb.Plugs.TokenAccess.call(%{})
      assert conn.status == 403
      assert conn.halted
    end

    test "incorrect bearer token results in 403", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "baconbaconbacon")
        |> TsundokuWeb.Plugs.TokenAccess.call(%{})

      assert conn.status == 403
      assert conn.halted
    end

    test "valid token results in success", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> TsundokuWeb.Plugs.TokenAccess.call(%{})

      refute conn.halted
    end
  end
end
