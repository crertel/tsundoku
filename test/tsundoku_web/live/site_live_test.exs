defmodule TsundokuWeb.SiteLiveTest do
  use TsundokuWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Tsundoku.Bookmarks
  @moduletag :sitelive

  @create_attrs %{url: "https://www.example.com", display_name: "Example dot com"}
  @update_attrs %{url: "https://www.example2.com", display_name: "Example Two dot com"}
  @invalid_attrs %{url: nil}

  defp create_site(_) do
    user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
    {:ok, site} = Bookmarks.create_site(@create_attrs |> Map.put(:created_by_id, user.id))
    %{site: site, user: user}
  end

  describe "Index" do
    setup [:create_site]

    test "lists all sites", %{conn: conn, site: site, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _index_live, html} = live(conn, Routes.site_index_path(conn, :index))

      assert html =~ "Listing Sites"
      assert html =~ site.url
    end

    test "cannot view, edit, or delete another user's site", %{conn: conn, site: site} do
      stranger = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
      conn = log_in_user(conn, stranger)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, Routes.site_show_path(conn, :show, site))
      end

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, Routes.site_index_path(conn, :edit, site))
      end

      {:ok, index_live, _html} = live(conn, Routes.site_index_path(conn, :index))
      Process.flag(:trap_exit, true)
      catch_exit(render_hook(index_live, :delete, %{"id" => site.id}))
      assert Bookmarks.get_site(site.id) != nil
    end

    test "suggests quoted and unquoted tag search completions", %{conn: conn, user: user} do
      {:ok, physics_tag} =
        Bookmarks.create_tag(%{name: "Physics Engine", created_by_id: user.id})

      {:ok, business_tag} = Bookmarks.create_tag(%{name: "business", created_by_id: user.id})

      {:ok, _site} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/seed",
          "display_name" => "seed",
          "created_by_id" => user.id,
          "tags" => [physics_tag, business_tag]
        })

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index))

      html = view |> form("form", query_field: %{query: "tag:ph"}) |> render_change()
      assert html =~ ~s(tag:&quot;Physics Engine&quot;)

      html = view |> form("form", query_field: %{query: ~s(tag:"Bu)}) |> render_change()
      assert html =~ "tag:business"
    end

    test "live-updates the suggestion list as the user types", %{conn: conn, user: user} do
      {:ok, physics_tag} =
        Bookmarks.create_tag(%{name: "Physics Engine", created_by_id: user.id})

      {:ok, _site} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/seed",
          "display_name" => "seed",
          "created_by_id" => user.id,
          "tags" => [physics_tag]
        })

      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, Routes.site_index_path(conn, :index))

      html =
        index_live
        |> form("form", query_field: %{query: "tag:ph"})
        |> render_change()

      assert html =~ ~s(tag:&quot;Physics Engine&quot;)
    end

    test "saves new site", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      site_name = "site name #{:rand.uniform()}"
      site_url = "http://www.example.com/#{:rand.uniform()}"

      {:ok, index_live, _html} = live(conn, Routes.site_index_path(conn, :index))

      assert index_live |> element("a", "New Site") |> render_click() =~
               "New Site"

      assert_patch(index_live, Routes.site_index_path(conn, :new))

      assert index_live
             |> form("#site-form", site: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#site-form", site: %{display_name: site_name, url: site_url})
        |> render_submit()
        |> follow_redirect(conn, Routes.site_index_path(conn, :index))

      assert html =~ "Site created successfully"
      assert html =~ site_name
    end

    test "updates site in listing", %{conn: conn, site: site, user: user} do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, Routes.site_index_path(conn, :index))

      assert !is_nil(index_live |> element("#site-#{site.id}"))

      assert index_live
             |> element("#site-#{site.id} a[href=\"/sites/#{site.id}/edit\"]")
             |> render_click() =~ "Edit Site"

      assert_patch(index_live, Routes.site_index_path(conn, :edit, site))

      assert index_live
             |> form("#site-form", site: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#site-form", site: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.site_index_path(conn, :index))

      assert html =~ "Site updated successfully"
      assert html =~ "Example Two dot com"
    end

    test "deletes site in listing", %{conn: conn, site: site, user: user} do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, Routes.site_index_path(conn, :index))

      assert index_live |> element("#site-#{site.id} a[phx-click=\"delete\"]") |> render_click()
      refute has_element?(index_live, "#site-#{site.id}")
    end
  end

  describe "Show" do
    setup [:create_site]

    test "displays site", %{conn: conn, site: site, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _show_live, html} = live(conn, Routes.site_show_path(conn, :show, site))

      assert html =~ "Show Site"
      assert html =~ site.url
    end

    test "updates site within modal", %{conn: conn, site: site, user: user} do
      conn = log_in_user(conn, user)
      {:ok, show_live, _html} = live(conn, Routes.site_show_path(conn, :show, site))

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Site"

      assert_patch(show_live, Routes.site_show_path(conn, :edit, site))

      assert show_live
             |> form("#site-form", site: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        show_live
        |> form("#site-form", site: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.site_show_path(conn, :show, site))

      assert html =~ "Site updated successfully"
      assert html =~ "https://www.example2.com"
    end
  end
end
