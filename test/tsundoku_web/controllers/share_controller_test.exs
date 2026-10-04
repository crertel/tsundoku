defmodule TsundokuWeb.ShareControllerTest do
  use TsundokuWeb.ConnCase, async: true

  import Tsundoku.AccountsFixtures
  alias Tsundoku.Bookmarks

  defp share(conn, params), do: post(conn, Routes.share_path(conn, :receive), params)

  describe "POST /share when logged out" do
    test "redirects to log in and saves nothing", %{conn: conn} do
      conn = share(conn, %{"url" => "https://example.com/article"})

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
      assert get_session(conn, :user_return_to) == "/sites"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Log in"
      assert Bookmarks.list_global_sites() == []
    end
  end

  describe "POST /share when logged in" do
    setup :register_and_log_in_user

    test "saves the url and lands on the edit page", %{conn: conn, user: user} do
      conn = share(conn, %{"url" => "https://example.com/article", "title" => "An Article"})

      site = Bookmarks.get_user_bookmark_by_url("https://example.com/article", user.id)
      assert site.display_name == "An Article"
      assert site.created_by_id == user.id
      assert redirected_to(conn) == Routes.site_index_path(conn, :edit, site.id)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Saved."
    end

    test "falls back to the url as the title when the title is blank", %{conn: conn, user: user} do
      share(conn, %{"url" => "https://example.com/untitled", "title" => "   "})

      site = Bookmarks.get_user_bookmark_by_url("https://example.com/untitled", user.id)
      assert site.display_name == "https://example.com/untitled"
    end

    test "falls back to the url as the title when no title is sent", %{conn: conn, user: user} do
      share(conn, %{"url" => "https://example.com/no-title"})

      site = Bookmarks.get_user_bookmark_by_url("https://example.com/no-title", user.id)
      assert site.display_name == "https://example.com/no-title"
    end

    test "pulls the url out of the text field", %{conn: conn, user: user} do
      conn =
        share(conn, %{
          "title" => "Shared",
          "text" => "Check this out: https://example.com/from-text."
        })

      site = Bookmarks.get_user_bookmark_by_url("https://example.com/from-text", user.id)
      assert site.display_name == "Shared"
      assert redirected_to(conn) == Routes.site_index_path(conn, :edit, site.id)
    end

    test "pulls the url out of a url field that carries surrounding text", %{
      conn: conn,
      user: user
    } do
      share(conn, %{"url" => "Read https://example.com/embedded, it's good"})

      assert Bookmarks.get_user_bookmark_by_url("https://example.com/embedded", user.id)
    end

    test "opens the existing bookmark instead of saving a duplicate", %{conn: conn, user: user} do
      {:ok, existing} =
        Bookmarks.create_site(%{
          display_name: "Original",
          url: "https://example.com/dupe",
          created_by_id: user.id,
          tags: []
        })

      conn = share(conn, %{"url" => "https://example.com/dupe", "title" => "Again"})

      assert redirected_to(conn) == Routes.site_index_path(conn, :edit, existing.id)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Already saved"
      assert Bookmarks.count_user_sites(user.id) == 1
      assert Bookmarks.get_site!(existing.id).display_name == "Original"
    end

    test "saves a url another user already has", %{conn: conn, user: user} do
      other = user_fixture()

      {:ok, _} =
        Bookmarks.create_site(%{
          display_name: "Theirs",
          url: "https://example.com/shared",
          created_by_id: other.id,
          tags: []
        })

      share(conn, %{"url" => "https://example.com/shared"})

      assert Bookmarks.count_user_sites(user.id) == 1
      assert Bookmarks.count_user_sites(other.id) == 1
    end

    test "reports when the shared content has no url", %{conn: conn, user: user} do
      for params <- [%{}, %{"text" => "just some words"}, %{"url" => "", "text" => ""}] do
        conn = share(conn, params)

        assert redirected_to(conn) == Routes.site_index_path(conn, :index)
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Couldn't find a URL"
      end

      assert Bookmarks.count_user_sites(user.id) == 0
    end

    test "ignores non-http schemes", %{conn: conn, user: user} do
      conn = share(conn, %{"url" => "javascript:alert(1)"})

      assert redirected_to(conn) == Routes.site_index_path(conn, :index)
      assert Bookmarks.count_user_sites(user.id) == 0
    end
  end
end
