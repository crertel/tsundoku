defmodule BookmarkServerWeb.TagLiveTest do
  use BookmarkServerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BookmarkServer.Bookmarks

  @create_attrs %{name: "some name"}
  @update_attrs %{name: "some updated name"}
  @invalid_attrs %{name: ""}

  @moduletag :tags

  defp create_tag(_) do
    user =  BookmarkServer.AccountsFixtures.user_fixture(confirmed: true)
    {:ok, tag} = Bookmarks.create_tag(%{name: "some name", created_by_id: user.id})

    %{tag: tag, user: user}
  end

  describe "Index" do
    setup [:create_tag]

    test "lists all tags", %{conn: conn, tag: tag, user: user} do
      conn = log_in_user(conn, user)

      {:ok, _index_live, html} = live(conn, Routes.tag_index_path(conn, :index, page: 1, search: ""))

      assert html =~ "Listing Tags"
      assert html =~ tag.name
    end

    test "saves new tag", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, Routes.tag_index_path(conn, :index))

      assert index_live |> element("a", "New Tag") |> render_click() =~
               "New Tag"

      assert_patch(index_live, Routes.tag_index_path(conn, :new))

      assert index_live
             |> form("#tag-form", tag: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#tag-form", tag: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.tag_index_path(conn, :index))

      assert html =~ "Tag created successfully"
      assert html =~ "some name"
    end

    test "updates tag in listing", %{conn: conn, tag: tag, user: user} do
      conn = log_in_user(conn, user)
      {:ok, index_live, _html} = live(conn, Routes.tag_index_path(conn, :index))

      assert !is_nil( index_live |> element("#tag-#{tag.id}"))

      assert index_live
             |> element("#tag-#{tag.id} a[href=\"/tags/#{tag.id}/edit\"")
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

    @tag :uut
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
  end
end
