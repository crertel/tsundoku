defmodule BookmarkServerWeb.ApiExtensionTest do
  use BookmarkServerWeb.ConnCase, async: true

  import BookmarkServer.AccountsFixtures
  alias BookmarkServer.Accounts
  alias BookmarkServer.Bookmarks
  alias BookmarkServer.Repo

  setup %{conn: conn} do
    user = user_fixture()
    other_user = user_fixture()

    token = Accounts.generate_user_session_token(user)

    auth_header = {"authorization", "bearer #{Base.encode64(token)}"}

    {:ok, tag_a} = Bookmarks.create_tag(%{"name" => "alpha", "created_by_id" => user.id})
    {:ok, tag_b} = Bookmarks.create_tag(%{"name" => "beta", "created_by_id" => user.id})

    # Tag belonging to a different user — should not leak into list_tags response.
    {:ok, _stranger_tag} =
      Bookmarks.create_tag(%{"name" => "stranger", "created_by_id" => other_user.id})

    {:ok, my_site} =
      Bookmarks.create_site(%{
        "url" => "https://example.com/mine",
        "display_name" => "Mine",
        "created_by_id" => user.id,
        "tags" => [tag_a]
      })

    {:ok, stranger_site} =
      Bookmarks.create_site(%{
        "url" => "https://example.com/theirs",
        "display_name" => "Theirs",
        "created_by_id" => other_user.id,
        "tags" => []
      })

    %{
      conn: conn,
      user: user,
      other_user: other_user,
      token: token,
      auth_header: auth_header,
      tag_a: tag_a,
      tag_b: tag_b,
      my_site: my_site,
      stranger_site: stranger_site
    }
  end

  describe "GET /api/tags" do
    test "requires a token", %{conn: conn} do
      conn = get(conn, Routes.api_path(conn, :list_tags))
      assert conn.status == 403
    end

    test "returns the current user's tags only", %{conn: conn, auth_header: auth} do
      response =
        conn
        |> put_req_header(elem(auth, 0), elem(auth, 1))
        |> get(Routes.api_path(conn, :list_tags))
        |> json_response(200)

      names = response["tags"] |> Enum.map(& &1["name"]) |> Enum.sort()
      assert names == ["alpha", "beta"]
    end
  end

  describe "GET /api/find_bookmark" do
    test "requires a token", %{conn: conn} do
      conn = get(conn, Routes.api_path(conn, :find_bookmark, url: "https://example.com/mine"))
      assert conn.status == 403
    end

    test "returns the bookmark when the user owns it", %{
      conn: conn,
      auth_header: auth,
      my_site: site
    } do
      response =
        conn
        |> put_req_header(elem(auth, 0), elem(auth, 1))
        |> get(Routes.api_path(conn, :find_bookmark, url: site.url))
        |> json_response(200)

      assert response["bookmark"]["id"] == site.id
      assert response["bookmark"]["url"] == site.url
      assert response["bookmark"]["tags"] == ["alpha"]
    end

    test "returns 404 for another user's bookmark", %{
      conn: conn,
      auth_header: auth,
      stranger_site: stranger
    } do
      conn =
        conn
        |> put_req_header(elem(auth, 0), elem(auth, 1))
        |> get(Routes.api_path(conn, :find_bookmark, url: stranger.url))

      assert conn.status == 404
    end

    test "returns 404 when no bookmark matches", %{conn: conn, auth_header: auth} do
      conn =
        conn
        |> put_req_header(elem(auth, 0), elem(auth, 1))
        |> get(Routes.api_path(conn, :find_bookmark, url: "https://nope.example.com"))

      assert conn.status == 404
    end
  end

  describe "POST /api/import_bookmarks" do
    test "requires a token", %{conn: conn} do
      conn = post(conn, Routes.api_path(conn, :import_bookmarks))
      assert conn.status == 403
    end

    test "imports the user's bookmarks from an HTML file", %{
      conn: conn,
      auth_header: auth,
      user: user
    } do
      html = """
      <!DOCTYPE NETSCAPE-Bookmark-file-1>
      <DL><p>
        <DT><H3>Reading</H3>
        <DL><p>
          <DT><A HREF="https://example.com/imported">Imported page</A>
        </DL><p>
      </DL><p>
      """

      path = Path.join(System.tmp_dir!(), "bookmarks_#{System.unique_integer([:positive])}.html")
      File.write!(path, html)

      upload = %Plug.Upload{path: path, filename: "bookmarks.html", content_type: "text/html"}

      response =
        conn
        |> put_req_header(elem(auth, 0), elem(auth, 1))
        |> post(Routes.api_path(conn, :import_bookmarks), %{"file" => upload})
        |> json_response(200)

      assert response["url_count"] >= 1

      assert %BookmarkServer.Bookmarks.Site{} =
               Bookmarks.get_user_bookmark_by_url("https://example.com/imported", user.id)
               |> Repo.preload(:tags)
    end
  end
end
