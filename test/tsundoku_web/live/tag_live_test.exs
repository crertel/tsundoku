defmodule TsundokuWeb.TagLiveTest do
  use TsundokuWeb.ConnCase

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Tsundoku.Bookmarks

  @create_attrs %{name: "some name"}
  @update_attrs %{name: "some updated name"}
  @invalid_attrs %{name: ""}

  @moduletag :tags

  defp create_tag(_) do
    user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
    {:ok, tag} = Bookmarks.create_tag(%{name: "some name", created_by_id: user.id})

    %{tag: tag, user: user}
  end

  describe "Index" do
    setup [:create_tag]

    test "lists all tags", %{conn: conn, tag: tag, user: user} do
      conn = log_in_user(conn, user)

      {:ok, _index_live, html} =
        live(conn, Routes.tag_index_path(conn, :index, page: 1, search: ""))

      assert html =~ "Listing Tags"
      assert html =~ tag.name
    end

    test "renders newly-broadcast tag after debounce", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, index_live, html} =
        live(conn, Routes.tag_index_path(conn, :index, page: 1, search: ""))

      refute html =~ "broadcast-fresh"

      # Create the tag from outside the LV's own mutation handlers —
      # the same shape as the extension API or another browser tab
      # saving a bookmark.
      {:ok, _} = Bookmarks.create_tag(%{name: "broadcast-fresh", created_by_id: user.id})

      # LiveHelpers debounce is 500ms; give it a bit of slack.
      Process.sleep(700)

      assert render(index_live) =~ "broadcast-fresh"
    end

    test "keeps the search when paging and starts a new search on page 1", %{
      conn: conn,
      user: user
    } do
      for n <- 10..29 do
        {:ok, _} = Bookmarks.create_tag(%{name: "match#{n}", created_by_id: user.id})
      end

      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, Routes.tag_index_path(conn, :index, search: "match"))

      index_live |> element(~s(a[phx-click="nav"][phx-value-page="2"]), "2") |> render_click()
      assert_patch(index_live, Routes.tag_index_path(conn, :index, page: 2, search: "match"))

      html = render(index_live)
      assert html =~ "match29"
      refute html =~ "some name"

      index_live |> form("#tag-search-form", query_field: %{query: "match1"}) |> render_change()
      assert_patch(index_live, Routes.tag_index_path(conn, :index, page: 1, search: "match1"))
    end

    test "treats % and _ in the search box literally", %{conn: conn, user: user} do
      {:ok, _} = Bookmarks.create_tag(%{name: "100%", created_by_id: user.id})
      {:ok, _} = Bookmarks.create_tag(%{name: "snake_case", created_by_id: user.id})

      conn = log_in_user(conn, user)

      {:ok, _live, html} = live(conn, Routes.tag_index_path(conn, :index, search: "%"))
      assert html =~ "100%"
      refute html =~ "snake_case"
      refute html =~ "some name"

      {:ok, _live, html} = live(conn, Routes.tag_index_path(conn, :index, search: "_"))
      assert html =~ "snake_case"
      refute html =~ "some name"
    end

    test "cannot view, edit, or delete another user's tag", %{conn: conn, tag: tag} do
      stranger = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
      conn = log_in_user(conn, stranger)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, Routes.tag_show_path(conn, :show, tag))
      end

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, Routes.tag_index_path(conn, :edit, tag))
      end

      {:ok, index_live, _html} = live(conn, Routes.tag_index_path(conn, :index))
      Process.flag(:trap_exit, true)
      catch_exit(render_hook(index_live, :delete, %{"id" => tag.id}))
      assert Bookmarks.get_tag(tag.id) != nil
    end

    @tag :uut
    test "saves new tag", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, Routes.tag_index_path(conn, :index))

      assert index_live |> element("a", "New Tag") |> render_click() =~
               "New Tag"

      assert_patch(index_live, Routes.tag_index_path(conn, :new))

      assert index_live
             |> form("#tag-form", tag: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      tag_name = "tag-#{:rand.uniform()}"
      tag_info = @create_attrs |> Map.put(:name, tag_name)

      {:ok, _, html} =
        index_live
        |> form("#tag-form", tag: tag_info)
        |> render_submit()
        |> follow_redirect(conn, Routes.tag_index_path(conn, :index))

      assert html =~ "Tag created successfully"
      assert html =~ tag_name
    end

    test "updates tag in listing", %{conn: conn, tag: tag, user: user} do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, Routes.tag_index_path(conn, :index))

      assert !is_nil(index_live |> element("#tag-#{tag.id}"))

      assert index_live
             |> element("#tag-#{tag.id} a[href=\"/tags/#{tag.id}/edit\"]")
             |> render_click() =~ "Edit Tag"

      assert_patch(index_live, Routes.tag_index_path(conn, :edit, tag))

      assert index_live
             |> form("#tag-form", tag: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#tag-form", tag: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.tag_index_path(conn, :index))

      assert html =~ "Tag updated successfully"
      assert html =~ "some updated name"
    end

    test "deletes tag in listing", %{conn: conn, tag: tag, user: user} do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, Routes.tag_index_path(conn, :index))

      assert index_live |> element("#tag-#{tag.id} a[phx-click=\"delete\"]") |> render_click()
      refute has_element?(index_live, "#tag-#{tag.id}")
    end
  end

  describe "Show" do
    setup [:create_tag]

    test "displays tag", %{conn: conn, tag: tag, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _show_live, html} = live(conn, Routes.tag_show_path(conn, :show, tag))

      assert html =~ "Show Tag"
      assert html =~ tag.name
    end

    test "updates tag within modal", %{conn: conn, tag: tag, user: user} do
      conn = log_in_user(conn, user)
      {:ok, show_live, _html} = live(conn, Routes.tag_show_path(conn, :show, tag))

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Tag"

      assert_patch(show_live, Routes.tag_show_path(conn, :edit, tag))

      assert show_live
             |> form("#tag-form", tag: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        show_live
        |> form("#tag-form", tag: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.tag_show_path(conn, :show, tag))

      assert html =~ "Tag updated successfully"
      assert html =~ "some updated name"
    end

    test "shows the description, bookmark count, and co-occurring tags", %{conn: conn, user: user} do
      {:ok, tag} =
        Bookmarks.create_tag(%{
          name: "elixir",
          description: "the language",
          created_by_id: user.id
        })

      {:ok, web} = Bookmarks.create_tag(%{name: "web", created_by_id: user.id})
      site_fixture(user, [tag, web])
      site_fixture(user, [tag])

      conn = log_in_user(conn, user)
      {:ok, show_live, html} = live(conn, Routes.tag_show_path(conn, :show, tag))

      assert html =~ "the language"
      assert html =~ "Often appears with"
      assert has_element?(show_live, ~s(a[href="/sites?q=tag%3Aelixir"]), "2")
      assert has_element?(show_live, ~s(a[href="/sites?q=tag%3Aelixir+tag%3Aweb"]), "web")
      assert has_element?(show_live, "button", "Delete 2 bookmarks")
    end

    test "hides the stats sections for an unused tag", %{conn: conn, tag: tag, user: user} do
      conn = log_in_user(conn, user)
      {:ok, _show_live, html} = live(conn, Routes.tag_show_path(conn, :show, tag))

      assert html =~ "0"
      refute html =~ "Often appears with"
      refute html =~ "Saves over time"
      refute html =~ "Delete all bookmarks with this tag"
      assert html =~ "No other tags to merge into."
    end

    test "draws a sparkline once saves span more than one month", %{
      conn: conn,
      tag: tag,
      user: user
    } do
      january = site_fixture(user, [tag])
      april = site_fixture(user, [tag])
      set_inserted_at(january, ~U[2026-01-15 12:00:00.000000Z])
      set_inserted_at(april, ~U[2026-04-15 12:00:00.000000Z])

      conn = log_in_user(conn, user)
      {:ok, show_live, html} = live(conn, Routes.tag_show_path(conn, :show, tag))

      assert html =~ "Saves over time"
      assert html =~ "Jan 2026"
      assert html =~ "Apr 2026"

      # Four months (Jan through Apr, gaps filled with zero) give four points.
      points = show_live |> element("polyline") |> render()
      assert [_, coords] = Regex.run(~r/points="([^"]*)"/, points)
      assert length(String.split(coords, " ")) == 4
    end

    test "omits the sparkline when every save is in the same month", %{
      conn: conn,
      tag: tag,
      user: user
    } do
      site_fixture(user, [tag])
      site_fixture(user, [tag])

      conn = log_in_user(conn, user)
      {:ok, _show_live, html} = live(conn, Routes.tag_show_path(conn, :show, tag))

      refute html =~ "Saves over time"
      assert html =~ "Delete 2 bookmarks"
    end

    test "deleting tagged bookmarks requires typing the tag name", %{
      conn: conn,
      tag: tag,
      user: user
    } do
      site_fixture(user, [tag])
      untagged = site_fixture(user, [])

      conn = log_in_user(conn, user)
      {:ok, show_live, html} = live(conn, Routes.tag_show_path(conn, :show, tag))
      assert html =~ "Delete 1 bookmark"

      html =
        show_live
        |> form(~s(form[phx-submit="delete_tagged_sites"]), confirm: %{name: "wrong"})
        |> render_submit()

      assert html =~ "Nothing deleted"
      assert Bookmarks.count_sites_for_tag(tag) == 1

      html =
        show_live
        |> form(~s(form[phx-submit="delete_tagged_sites"]), confirm: %{name: " some name "})
        |> render_submit()

      assert html =~ "Deleted 1 bookmark(s)"
      refute html =~ "Delete all bookmarks with this tag"
      assert Bookmarks.count_sites_for_tag(tag) == 0
      assert Bookmarks.get_site(untagged.id)
      assert Bookmarks.get_tag(tag.id)
    end

    test "merges the tag into another and returns to the tag list", %{
      conn: conn,
      tag: tag,
      user: user
    } do
      {:ok, dest} = Bookmarks.create_tag(%{name: "destination", created_by_id: user.id})
      site = site_fixture(user, [tag])

      conn = log_in_user(conn, user)
      {:ok, show_live, _html} = live(conn, Routes.tag_show_path(conn, :show, tag))

      {:ok, _, html} =
        show_live
        |> form(~s(form[phx-submit="merge"]), merge: %{dest_name: " destination "})
        |> render_submit()
        |> follow_redirect(conn, Routes.tag_index_path(conn, :index))

      assert html =~ "1 bookmark(s) moved"
      assert Bookmarks.get_tag(tag.id) == nil
      assert Bookmarks.count_sites_for_tag(dest) == 1
      assert Bookmarks.get_site(site.id)
    end

    test "refuses to merge into an unknown tag or into itself", %{
      conn: conn,
      tag: tag,
      user: user
    } do
      {:ok, _other} = Bookmarks.create_tag(%{name: "other", created_by_id: user.id})

      conn = log_in_user(conn, user)
      {:ok, show_live, _html} = live(conn, Routes.tag_show_path(conn, :show, tag))

      html =
        show_live
        |> form(~s(form[phx-submit="merge"]), merge: %{dest_name: "nope"})
        |> render_submit()

      assert html =~ "No tag named"
      assert html =~ ~s(value="nope")

      html =
        show_live
        |> form(~s(form[phx-submit="merge"]), merge: %{dest_name: "some name"})
        |> render_submit()

      assert html =~ "merge a tag into itself"
      assert Bookmarks.get_tag(tag.id)
    end
  end

  defp site_fixture(user, tags) do
    {:ok, site} =
      Bookmarks.create_site(%{
        "url" => "https://example.com/#{System.unique_integer([:positive])}",
        "created_by_id" => user.id,
        "tags" => tags
      })

    site
  end

  defp set_inserted_at(site, at) do
    Tsundoku.Repo.update_all(from(s in Tsundoku.Bookmarks.Site, where: s.id == ^site.id),
      set: [inserted_at: at]
    )
  end
end
