defmodule BookmarkServerWeb.ApiTest do
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

    %{user: user, conn: conn, token: token,}
  end

  describe "creation of user" do
    test "fails without token", %{conn: conn, user: _user} do
      path = Routes.api_path(conn, :create_user)
      conn = conn |> post( path, %{} )
      assert conn.status == 403
      assert conn.halted
    end

    test "fails with invalid token", %{conn: conn, user: _user} do
      path = Routes.api_path(conn, :create_user)
      conn = conn
        |> put_req_header("authorization", "baconbaconbacon")
        |> post( path, %{} )
      assert conn.status == 403
      assert conn.halted
    end

    test "fails with correct token and bad params", %{conn: conn, user: _user, token: token} do
      path = Routes.api_path(conn, :create_user)
      conn = conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post( path, %{} )
      assert conn.status == 400
      assert conn.halted
    end

    test "fails with correct token and good params but reused email", %{conn: conn, user: user, token: token} do
      path = Routes.api_path(conn, :create_user)
      conn = conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post( path, %{"email"=>user.email, "password"=>"passwordpassword"} )
      assert conn.status == 500
      assert conn.halted
    end

    test "succeeds with correct token and good params", %{conn: conn, user: _user, token: token} do
      path = Routes.api_path(conn, :create_user)
      conn = conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post( path, %{"email"=>"testuser@example.com", "password"=>"passwordpassword"} )
      assert conn.status == 201
      refute conn.halted
    end
  end


  describe "create bookmark" do
    test "fails without token", %{conn: conn, user: _user} do
    path = Routes.api_path(conn, :create_bookmark)
      conn = conn |> post( path, %{} )
      assert conn.status == 403
      assert conn.halted
    end

    test "fails with invalid token", %{conn: conn, user: _user} do
      path = Routes.api_path(conn, :create_bookmark)
      conn = conn
        |> put_req_header("authorization", "baconbaconbacon")
        |> post( path, %{} )
      assert conn.status == 403
      assert conn.halted
    end

    @good_bookmark %{
      "url" => "https://www.example.com",
      "title" => "test site",
      "tags" => ["a","b",]
    }

    test "fails with correct token and bad params", %{conn: conn, token: token} do
      path = Routes.api_path(conn, :create_bookmark)
      conn = conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post( path, %{} )
      assert conn.status == 400
      assert conn.halted
    end

    test "succeeds with correct token and good params", %{conn: conn, user: _user, token: token} do
      path = Routes.api_path(conn, :create_bookmark)
      conn = conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post( path, @good_bookmark )
      assert conn.status == 201
    end
  end

  describe "create tag" do
    @describetag :uut
    test "fails without token", %{conn: conn, user: _user} do
    path = Routes.api_path(conn, :create_tag)
      conn = conn |> post( path, %{} )
      assert conn.status == 403
      assert conn.halted
    end

    test "fails with invalid token", %{conn: conn, user: _user} do
      path = Routes.api_path(conn, :create_tag)
      conn = conn
        |> put_req_header("authorization", "baconbaconbacon")
        |> post( path, %{} )
      assert conn.status == 403
      assert conn.halted
    end

  @good_tag %{
      "name" => "test tag",
    }

    test "fails with correct token and bad params", %{conn: conn, token: token} do
      path = Routes.api_path(conn, :create_tag)
      conn = conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post( path, %{} )
      assert conn.status == 400
      assert conn.halted
    end

    test "succeeds with correct token and good params", %{conn: conn, user: _user, token: token} do
      path = Routes.api_path(conn, :create_tag)
      conn = conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post( path, @good_tag )
      assert conn.status == 201
    end
  end


end
