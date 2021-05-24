defmodule BookmarkServerWeb.ApiTest do
  use BookmarkServerWeb.ConnCase, async: true

  import BookmarkServer.AccountsFixtures
  alias BookmarkServer.Accounts
  alias BookmarkServer.Repo

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, BookmarkServerWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    user = user_fixture()
    token = Accounts.generate_user_session_token(user)

    tags = ["a","b","c"] |> Enum.map( fn tag ->
      {:ok, tag} = BookmarkServer.Bookmarks.create_tag(%{name: tag})
      tag
    end)

    {:ok, bookmark} = BookmarkServer.Bookmarks.create_site(%{
      "created_by_id" => user.id,
      "display_name" => "test title",
      "url" => "https://www.example.com",
      "tags" => tags
    })

    bm = bookmark
    |> Repo.preload(:tags)
    |> Repo.preload(:created_by)

    %{user: user, conn: conn, token: token, bookmark: bm}
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
      "tags" => ["a","b"]
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

  describe "update bookmark" do
    @describetag :uut

    test "fails without token", %{conn: conn, bookmark: bookmark} do
    path = Routes.api_path(conn, :update_bookmark, bookmark.id)
      conn = conn |> post( path, %{} )
      assert conn.status == 403
      assert conn.halted
    end

    test "fails with invalid token", %{conn: conn, bookmark: bookmark} do
      path = Routes.api_path(conn, :update_bookmark, bookmark.id)
      conn = conn
        |> put_req_header("authorization", "baconbaconbacon")
        |> post( path, %{} )
      assert conn.status == 403
      assert conn.halted
    end

    test "fails with correct token and bad params", %{conn: conn, bookmark: bookmark, token: token} do
      path = Routes.api_path(conn, :update_bookmark, bookmark.id)
      conn = conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post( path, %{} )
      assert conn.status == 400
      assert conn.halted
    end

    test "succeeds with correct token and good params", %{conn: conn, bookmark: bookmark, token: token} do
      path = Routes.api_path(conn, :update_bookmark, bookmark.id)

      conn = conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post( path, %{
          "url" => "https://www.example.com/alternate",
          "title" => "test site 2",
          "tags" => ["c","d"]
        } )
      {:ok, response} = Jason.decode(conn.resp_body)

      assert conn.status == 201
      assert response["id"] == bookmark.id
      assert response["created_by"] == bookmark.created_by.id
      assert response["tags"] == ["d","c"]
    end
  end

  describe "create tag" do
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
