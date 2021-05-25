defmodule BookmarkServerWeb.ApiBookmarkTest do
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

    {:ok, tag} = BookmarkServer.Bookmarks.create_tag(%{
      "created_by_id" => user.id,
      "name" => "tag"
    })

    bm = bookmark
    |> Repo.preload(:tags)
    |> Repo.preload(:created_by)

    t = tag |> Repo.preload(:created_by)

    %{user: user, conn: conn, token: token, bookmark: bm, tag: t}
  end

  describe "get bookmark" do
    test "fails without token", %{conn: conn, bookmark: bookmark} do
      path = Routes.api_path(conn, :get_bookmark, bookmark.id)
        conn = conn |> get( path)
        assert conn.status == 403
        assert conn.halted
      end

      test "fails with invalid token", %{conn: conn, bookmark: bookmark} do
        path = Routes.api_path(conn, :get_bookmark, bookmark.id)
        conn = conn
          |> put_req_header("authorization", "baconbaconbacon")
          |> get( path)
        assert conn.status == 403
        assert conn.halted
      end

      test "fails with correct token and bad id", %{conn: conn, token: token} do
        path = Routes.api_path(conn, :get_bookmark, "lolwut")
        conn = conn
          |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
          |> get( path )
        assert conn.status == 404
        assert conn.halted
      end

      test "succeeds with correct token and good params", %{conn: conn, bookmark: bookmark, token: token} do
        path = Routes.api_path(conn, :get_bookmark, bookmark.id)

        conn = conn
          |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
          |> get( path )
        {:ok, response} = Jason.decode(conn.resp_body)

        assert conn.status == 200
        assert response["id"] == bookmark.id
        assert response["created_by"] == bookmark.created_by.id
        assert response["tags"] == ["a","b","c"]
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


end
