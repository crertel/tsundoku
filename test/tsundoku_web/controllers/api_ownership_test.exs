defmodule TsundokuWeb.ApiOwnershipTest do
  use TsundokuWeb.ConnCase, async: true

  import Tsundoku.AccountsFixtures
  alias Tsundoku.Accounts
  alias Tsundoku.Bookmarks
  alias Tsundoku.Repo

  setup %{conn: conn} do
    user = user_fixture()
    other_user = user_fixture()
    token = user |> Accounts.generate_user_session_token() |> Base.encode64()

    {:ok, my_tag} = Bookmarks.create_tag(%{"name" => "mine", "created_by_id" => user.id})

    {:ok, their_tag} =
      Bookmarks.create_tag(%{"name" => "theirs", "created_by_id" => other_user.id})

    {:ok, my_site} =
      Bookmarks.create_site(%{
        "url" => "https://example.com/mine",
        "display_name" => "Mine",
        "created_by_id" => user.id,
        "tags" => [my_tag]
      })

    {:ok, their_site} =
      Bookmarks.create_site(%{
        "url" => "https://example.com/theirs",
        "display_name" => "Theirs",
        "created_by_id" => other_user.id,
        "tags" => [their_tag]
      })

    %{
      conn: put_req_header(conn, "authorization", "bearer #{token}"),
      user: user,
      other_user: other_user,
      my_tag: my_tag,
      their_tag: their_tag,
      my_site: my_site,
      their_site: their_site
    }
  end

  describe "bookmarks" do
    test "can't read another user's bookmark", %{conn: conn, their_site: their_site} do
      conn = get(conn, Routes.api_path(conn, :get_bookmark, their_site.id))

      assert json_response(conn, 403) == %{}
    end

    test "404s reading a bookmark that doesn't exist", %{conn: conn} do
      conn = get(conn, Routes.api_path(conn, :get_bookmark, Ecto.UUID.generate()))

      assert json_response(conn, 404) == %{}
    end

    test "can't update another user's bookmark", %{conn: conn, their_site: their_site} do
      conn =
        post(conn, Routes.api_path(conn, :update_bookmark, their_site.id), %{
          "title" => "Hijacked",
          "url" => "https://example.com/hijacked",
          "tags" => []
        })

      assert json_response(conn, 403) == %{}
      assert %{display_name: "Theirs", url: "https://example.com/theirs"} = reload(their_site)
    end

    test "404s updating a bookmark that doesn't exist", %{conn: conn} do
      conn =
        post(conn, Routes.api_path(conn, :update_bookmark, Ecto.UUID.generate()), %{
          "title" => "x",
          "url" => "https://example.com/x",
          "tags" => []
        })

      assert json_response(conn, 404) == %{}
    end

    test "updating reuses the user's existing tags and creates missing ones", %{
      conn: conn,
      user: user,
      my_site: my_site,
      my_tag: my_tag
    } do
      conn =
        post(conn, Routes.api_path(conn, :update_bookmark, my_site.id), %{
          "title" => "Renamed",
          "url" => "https://example.com/mine",
          "notes" => "some notes",
          "tags" => ["mine", "brand-new"]
        })

      assert %{"title" => "Renamed", "tags" => tags} = json_response(conn, 201)
      assert Enum.sort(tags) == ["brand-new", "mine"]

      site = my_site |> reload() |> Repo.preload(:tags)
      assert site.notes == "some notes"
      assert my_tag.id in Enum.map(site.tags, & &1.id)
      assert length(Bookmarks.list_user_tags(user.id)) == 2
    end

    test "find_bookmark needs a url", %{conn: conn} do
      conn = get(conn, Routes.api_path(conn, :find_bookmark))

      assert json_response(conn, 400) == %{}
    end
  end

  describe "tags" do
    test "can't read another user's tag", %{conn: conn, their_tag: their_tag} do
      conn = get(conn, Routes.api_path(conn, :get_tag, their_tag.id))

      assert json_response(conn, 403) == %{}
    end

    test "404s reading a tag that doesn't exist", %{conn: conn} do
      conn = get(conn, Routes.api_path(conn, :get_tag, Ecto.UUID.generate()))

      assert json_response(conn, 404) == %{}
    end

    test "can't rename another user's tag", %{conn: conn, their_tag: their_tag} do
      conn = post(conn, Routes.api_path(conn, :update_tag, their_tag.id), %{"name" => "hijacked"})

      assert json_response(conn, 403) == %{}
      assert Bookmarks.get_tag(their_tag.id).name == "theirs"
    end

    test "404s renaming a tag that doesn't exist", %{conn: conn} do
      conn =
        post(conn, Routes.api_path(conn, :update_tag, Ecto.UUID.generate()), %{"name" => "x"})

      assert json_response(conn, 404) == %{}
    end
  end

  describe "GET /api/random_bookmark" do
    test "returns one of the user's own bookmarks", %{conn: conn, my_site: my_site} do
      conn = get(conn, Routes.api_path(conn, :random_bookmark))

      assert json_response(conn, 200) == %{
               "bookmark" => %{
                 "id" => my_site.id,
                 "url" => "https://example.com/mine",
                 "display_name" => "Mine"
               }
             }
    end

    test "404s when the user has no bookmarks", %{conn: conn, my_site: my_site} do
      {:ok, _} = Bookmarks.delete_site(my_site)

      conn = get(conn, Routes.api_path(conn, :random_bookmark))

      assert json_response(conn, 404) == %{}
    end
  end

  describe "imports" do
    @bookmarks_html """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <DL><p>
      <DT><H3>Reading</H3>
      <DL><p>
        <DT><A HREF="https://example.com/imported">Imported page</A>
      </DL><p>
    </DL><p>
    """

    defp start_import(conn) do
      path = Path.join(System.tmp_dir!(), "bookmarks_#{System.unique_integer([:positive])}.html")
      File.write!(path, @bookmarks_html)
      on_exit(fn -> File.rm(path) end)

      upload = %Plug.Upload{path: path, filename: "bookmarks.html", content_type: "text/html"}

      conn
      |> post(Routes.api_path(conn, :import_bookmarks), %{"file" => upload})
      |> json_response(202)
      |> Map.fetch!("job_id")
    end

    test "import_bookmarks needs a file", %{conn: conn} do
      conn = post(conn, Routes.api_path(conn, :import_bookmarks), %{})

      assert json_response(conn, 400) == %{}
    end

    test "import_status reports a queued job and then its result", %{conn: conn} do
      job_id = start_import(conn)

      assert %{"state" => "available", "stage" => "queued", "processed" => 0, "total" => 0} =
               conn |> get(Routes.api_path(conn, :import_status, job_id)) |> json_response(200)

      assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :import, with_safety: false)

      assert %{
               "state" => "completed",
               "stage" => "complete",
               "processed" => 1,
               "total" => 1,
               "sites_inserted" => 1,
               "tags_inserted" => 1
             } = conn |> get(Routes.api_path(conn, :import_status, job_id)) |> json_response(200)
    end

    test "import_status hides other users' jobs", %{conn: conn, other_user: other_user} do
      job_id = start_import(conn)

      other_token = other_user |> Accounts.generate_user_session_token() |> Base.encode64()

      other_conn =
        build_conn()
        |> put_req_header("authorization", "bearer #{other_token}")
        |> get(Routes.api_path(conn, :import_status, job_id))

      assert json_response(other_conn, 404) == %{"msg" => "not found"}
    end

    test "import_status 404s for unknown or malformed job ids", %{conn: conn} do
      for id <- ["999999999", "abc", "12abc"] do
        conn = get(conn, Routes.api_path(conn, :import_status, id))

        assert json_response(conn, 404) == %{"msg" => "not found"}
      end
    end
  end

  describe "validation errors" do
    test "creating a bookmark at a url the user already has", %{conn: conn, user: user} do
      conn =
        post(conn, Routes.api_path(conn, :create_bookmark), %{
          "title" => "Again",
          "url" => "https://example.com/mine",
          "tags" => []
        })

      assert %{"msg" => msg, "errors" => %{"url" => [_]}} = json_response(conn, 422)
      assert msg =~ "you already have a bookmark at this URL"
      assert conn.halted
      assert Bookmarks.count_user_sites(user.id) == 1
    end

    test "creating a bookmark with an invalid url", %{conn: conn, user: user} do
      conn =
        post(conn, Routes.api_path(conn, :create_bookmark), %{
          "title" => "Bad",
          "url" => "not a url",
          "tags" => ["fresh"]
        })

      assert %{"msg" => "url: Invalid URL", "errors" => %{"url" => ["Invalid URL"]}} =
               json_response(conn, 422)

      assert Bookmarks.count_user_sites(user.id) == 1
    end

    test "creating a bookmark with tags that aren't a list", %{conn: conn} do
      conn =
        post(conn, Routes.api_path(conn, :create_bookmark), %{
          "title" => "x",
          "url" => "https://example.com/x",
          "tags" => "nope"
        })

      assert json_response(conn, 400) == %{}
    end

    test "creating a bookmark trims, dedupes, and drops blank tags", %{conn: conn, user: user} do
      conn =
        post(conn, Routes.api_path(conn, :create_bookmark), %{
          "title" => "Tagged",
          "url" => "https://example.com/tagged",
          "tags" => [" fresh ", "fresh", "", "mine"]
        })

      assert json_response(conn, 201) == %{}

      site =
        "https://example.com/tagged"
        |> Bookmarks.get_user_bookmark_by_url(user.id)
        |> Repo.preload(:tags)

      assert site.tags |> Enum.map(& &1.name) |> Enum.sort() == ["fresh", "mine"]
      assert length(Bookmarks.list_user_tags(user.id)) == 2
    end

    test "updating a bookmark to an invalid url", %{conn: conn, my_site: my_site} do
      conn =
        post(conn, Routes.api_path(conn, :update_bookmark, my_site.id), %{
          "title" => "Mine",
          "url" => "not a url",
          "tags" => []
        })

      assert %{"errors" => %{"url" => ["Invalid URL"]}} = json_response(conn, 422)
      assert reload(my_site).url == "https://example.com/mine"
    end

    test "creating a tag with a blank or taken name", %{conn: conn, user: user} do
      blank = post(conn, Routes.api_path(conn, :create_tag), %{"name" => ""})
      assert %{"errors" => %{"name" => ["can't be blank"]}} = json_response(blank, 422)

      taken = post(conn, Routes.api_path(conn, :create_tag), %{"name" => "mine"})
      assert %{"msg" => msg} = json_response(taken, 422)
      assert msg =~ "you already have a tag with this name"

      assert length(Bookmarks.list_user_tags(user.id)) == 1
    end

    test "renaming a tag to a blank or taken name", %{conn: conn, user: user, my_tag: my_tag} do
      {:ok, _} = Bookmarks.create_tag(%{"name" => "other", "created_by_id" => user.id})

      blank = post(conn, Routes.api_path(conn, :update_tag, my_tag.id), %{"name" => ""})
      assert %{"errors" => %{"name" => ["can't be blank"]}} = json_response(blank, 422)

      taken = post(conn, Routes.api_path(conn, :update_tag, my_tag.id), %{"name" => "other"})
      assert %{"msg" => msg} = json_response(taken, 422)
      assert msg =~ "you already have a tag with this name"

      assert Bookmarks.get_tag(my_tag.id).name == "mine"
    end

    test "creating a user with a password that's too short", %{conn: conn} do
      conn =
        post(conn, Routes.api_path(conn, :create_user), %{
          "email" => unique_user_email(),
          "password" => "short"
        })

      assert %{"errors" => %{"password" => [_]}} = json_response(conn, 422)
    end

    test "importing a file that can't be read", %{conn: conn} do
      upload = %Plug.Upload{
        path: Path.join(System.tmp_dir!(), "missing_#{System.unique_integer([:positive])}.html"),
        filename: "bookmarks.html",
        content_type: "text/html"
      }

      conn = post(conn, Routes.api_path(conn, :import_bookmarks), %{"file" => upload})

      assert %{"msg" => msg} = json_response(conn, 422)
      assert msg =~ "Couldn't read that file"
    end
  end

  describe "malformed ids" do
    test "404 instead of raising", %{conn: conn} do
      bookmark = %{"title" => "x", "url" => "https://example.com/x", "tags" => []}

      assert conn |> get(Routes.api_path(conn, :get_bookmark, "nope")) |> json_response(404)
      assert conn |> get(Routes.api_path(conn, :get_tag, "nope")) |> json_response(404)

      assert conn
             |> post(Routes.api_path(conn, :update_bookmark, "nope"), bookmark)
             |> json_response(404)

      assert conn
             |> post(Routes.api_path(conn, :update_tag, "nope"), %{"name" => "x"})
             |> json_response(404)
    end
  end

  defp reload(site), do: Bookmarks.get_site!(site.id)
end
