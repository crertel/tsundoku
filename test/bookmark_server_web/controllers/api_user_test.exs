defmodule BookmarkServerWeb.ApiUserTest do
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

  describe "creation of user" do
    test "fails without token", %{conn: conn, user: _user} do
      path = Routes.api_path(conn, :create_user)
      conn = conn |> post(path, %{})
      assert conn.status == 403
      assert conn.halted
    end

    test "fails with invalid token", %{conn: conn, user: _user} do
      path = Routes.api_path(conn, :create_user)

      conn =
        conn
        |> put_req_header("authorization", "baconbaconbacon")
        |> post(path, %{})

      assert conn.status == 403
      assert conn.halted
    end

    test "fails with correct token and bad params", %{conn: conn, user: _user, token: token} do
      path = Routes.api_path(conn, :create_user)

      conn =
        conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post(path, %{})

      assert conn.status == 400
      assert conn.halted
    end

    test "fails with correct token and good params but reused email", %{
      conn: conn,
      user: user,
      token: token
    } do
      path = Routes.api_path(conn, :create_user)

      conn =
        conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post(path, %{"email" => user.email, "password" => "passwordpassword"})

      assert conn.status == 500
      assert conn.halted
    end

    test "succeeds with correct token and good params", %{conn: conn, user: _user, token: token} do
      path = Routes.api_path(conn, :create_user)

      conn =
        conn
        |> put_req_header("authorization", "bearer #{Base.encode64(token)}")
        |> post(path, %{"email" => "testuser@example.com", "password" => "passwordpassword"})

      assert conn.status == 201
      refute conn.halted
    end
  end
end
