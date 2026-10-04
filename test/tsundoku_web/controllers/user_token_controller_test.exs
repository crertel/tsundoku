defmodule TsundokuWeb.UserTokenControllerTest do
  use TsundokuWeb.ConnCase, async: true

  import Tsundoku.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  defp login(conn, params), do: post(conn, Routes.user_token_path(conn, :new), params)

  describe "POST /api/login" do
    test "returns a token that authenticates API requests", %{conn: conn, user: user} do
      conn = login(conn, %{"username" => user.email, "password" => valid_user_password()})

      assert %{"token" => token} = json_response(conn, 201)

      authed =
        build_conn()
        |> put_req_header("authorization", "bearer #{token}")
        |> get(Routes.api_path(conn, :test))

      assert authed.status == 200
    end

    test "rejects a wrong password", %{conn: conn, user: user} do
      conn = login(conn, %{"username" => user.email, "password" => "not the password"})

      assert json_response(conn, 403) == %{}
    end

    test "rejects an unknown user", %{conn: conn} do
      conn =
        login(conn, %{"username" => "nobody@example.com", "password" => valid_user_password()})

      assert json_response(conn, 403) == %{}
    end

    test "rejects requests missing credentials", %{conn: conn, user: user} do
      assert json_response(login(conn, %{}), 400) == %{}
      assert json_response(login(conn, %{"username" => user.email}), 400) == %{}
      assert json_response(login(conn, %{"password" => valid_user_password()}), 400) == %{}
    end
  end
end
