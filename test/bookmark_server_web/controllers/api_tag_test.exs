defmodule BookmarkServerWeb.ApiTagTest do
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

    tags =
      ["a", "b", "c"]
      |> Enum.map(fn tag ->
        {:ok, tag} = BookmarkServer.Bookmarks.create_tag(%{name: tag})
        tag
      end)

    {:ok, bookmark} =
      BookmarkServer.Bookmarks.create_site(%{
        "created_by_id" => user.id,
        "display_name" => "test title",
        "url" => "https://www.example.com",
        "tags" => tags
      })

    {:ok, tag} =
      BookmarkServer.Bookmarks.create_tag(%{
        "created_by_id" => user.id,
        "name" => "tag"
      })

    bm =
      bookmark
      |> Repo.preload(:tags)
      |> Repo.preload(:created_by)

    t = tag |> Repo.preload(:created_by)

    %{user: user, conn: conn, token: token, bookmark: bm, tag: t}
  end

  describe "get tag" do
    test "fails without token", %{conn: conn, tag: tag} do
      path = Routes.api_path(conn, :get_tag, tag.id)
      conn = conn |> get(path)
      assert conn.status == 403
      assert conn.halted
    end

    test "fails with invalid token", %{conn: conn, tag: tag} do
      path = Routes.api_path(conn, :get_tag, tag.id)

      conn =
        conn
        |> put_req_header("authorization", "baconbaconbacon")
        |> get(path)

      assert conn.status == 403
      assert conn.halted
    end

    test "fails with correct token and bad id", %{conn: conn, token: token} do
      path = Routes.api_path(conn, :get_tag, "lolwut")

      conn =
        conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> get(path)

      assert conn.status == 404
      assert conn.halted
    end

    test "succeeds with correct token and good params", %{conn: conn, tag: tag, token: token} do
      path = Routes.api_path(conn, :get_tag, tag.id)

      conn =
        conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> get(path)

      {:ok, response} = Jason.decode(conn.resp_body)

      assert conn.status == 200
      assert response["id"] == tag.id
      assert response["created_by"] == tag.created_by.id
      assert response["name"] == "tag"
    end
  end

  describe "create tag" do
    test "fails without token", %{conn: conn, user: _user} do
      path = Routes.api_path(conn, :create_tag)
      conn = conn |> post(path, %{})
      assert conn.status == 403
      assert conn.halted
    end

    test "fails with invalid token", %{conn: conn, user: _user} do
      path = Routes.api_path(conn, :create_tag)

      conn =
        conn
        |> put_req_header("authorization", "baconbaconbacon")
        |> post(path, %{})

      assert conn.status == 403
      assert conn.halted
    end

    @good_tag %{
      "name" => "test tag"
    }

    test "fails with correct token and bad params", %{conn: conn, token: token} do
      path = Routes.api_path(conn, :create_tag)

      conn =
        conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post(path, %{})

      assert conn.status == 400
      assert conn.halted
    end

    test "succeeds with correct token and good params", %{conn: conn, user: _user, token: token} do
      path = Routes.api_path(conn, :create_tag)

      conn =
        conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post(path, @good_tag)

      assert conn.status == 201
    end
  end

  describe "update tag" do
    test "fails without token", %{conn: conn, tag: tag} do
      path = Routes.api_path(conn, :update_tag, tag.id)
      conn = conn |> post(path, %{})
      assert conn.status == 403
      assert conn.halted
    end

    test "fails with invalid token", %{conn: conn, tag: tag} do
      path = Routes.api_path(conn, :update_tag, tag.id)

      conn =
        conn
        |> put_req_header("authorization", "baconbaconbacon")
        |> post(path, %{})

      assert conn.status == 403
      assert conn.halted
    end

    test "fails with correct token and bad params", %{conn: conn, tag: tag, token: token} do
      path = Routes.api_path(conn, :update_tag, tag.id)

      conn =
        conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post(path, %{})

      assert conn.status == 400
      assert conn.halted
    end

    test "succeeds with correct token and good params", %{conn: conn, tag: tag, token: token} do
      path = Routes.api_path(conn, :update_tag, tag.id)

      conn =
        conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post(path, %{
          "name" => "tag2"
        })

      {:ok, response} = Jason.decode(conn.resp_body)

      assert conn.status == 201
      assert response["id"] == tag.id
      assert response["created_by"] == tag.created_by.id
      assert response["name"] == "tag2"
    end
  end
end
