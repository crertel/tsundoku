defmodule TsundokuWeb.SavedSearchLiveTest do
  use TsundokuWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Tsundoku.Bookmarks

  setup %{conn: conn} do
    user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
    %{conn: log_in_user(conn, user), user: user}
  end

  defp saved_search_fixture(user, attrs \\ %{}) do
    {:ok, search} =
      %{name: "Elixir reading", query: "tag:elixir", created_by_id: user.id}
      |> Map.merge(attrs)
      |> Bookmarks.create_saved_search()

    search
  end

  defp click(view, event, search) do
    view
    |> element(~s(button[phx-click="#{event}"][phx-value-id="#{search.id}"]))
    |> render_click()
  end

  defp reload(search), do: Bookmarks.get_saved_search!(search.id)

  describe "Index" do
    test "shows an empty state", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/searches")

      assert html =~ "Saved searches"
      assert html =~ "No saved searches yet."
    end

    test "lists the user's searches and not anyone else's", %{conn: conn, user: user} do
      saved_search_fixture(user)
      saved_search_fixture(user, %{name: "Everything", query: ""})
      other = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
      saved_search_fixture(other, %{name: "Somebody else's"})

      {:ok, view, html} = live(conn, "/searches")

      assert html =~ "Elixir reading"
      assert html =~ "tag:elixir"
      assert html =~ "(empty query — all sites)"
      refute html =~ "Somebody else&#39;s"
      refute html =~ "Feed live"
      assert has_element?(view, ~s(a[href="/sites?q=tag%3Aelixir"]), "Run")
    end
  end

  describe "New" do
    test "sends you to the sites page when there's no query to save", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/sites"}}} = live(conn, "/searches/new")
      assert {:error, {:live_redirect, %{to: "/sites"}}} = live(conn, "/searches/new?query=++")
    end

    test "names and saves the query from the sites page", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, "/searches/new?query=tag:elixir+url:blog")

      assert html =~ "Name this search"
      assert html =~ "tag:elixir url:blog"

      view
      |> form(~s(form[phx-submit="save"]), saved_search: %{name: "Blog posts"})
      |> render_submit()

      assert_patch(view, "/searches")

      html = render(view)
      assert html =~ "Saved search saved."
      assert html =~ "Blog posts"
      refute html =~ "Name this search"

      assert [%{name: "Blog posts", query: "tag:elixir url:blog"}] =
               Bookmarks.list_user_saved_searches(user.id)
    end

    test "shows an error for a blank name", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, "/searches/new?query=tag:elixir")

      html =
        view
        |> form(~s(form[phx-submit="save"]), saved_search: %{name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert Bookmarks.list_user_saved_searches(user.id) == []
    end

    test "shows an error for a name that's already taken", %{conn: conn, user: user} do
      saved_search_fixture(user, %{name: "Taken"})
      {:ok, view, _html} = live(conn, "/searches/new?query=tag:rust")

      html =
        view
        |> form(~s(form[phx-submit="save"]), saved_search: %{name: "Taken"})
        |> render_submit()

      assert html =~ "you already have a saved search with this name"
      assert length(Bookmarks.list_user_saved_searches(user.id)) == 1
    end
  end

  describe "Edit" do
    test "renames a search and keeps its query", %{conn: conn, user: user} do
      search = saved_search_fixture(user)

      {:ok, view, _html} = live(conn, "/searches")

      assert view |> element(~s(a[href="/searches/#{search.id}/edit"])) |> render_click() =~
               "Edit saved search"

      assert_patch(view, "/searches/#{search.id}/edit")

      view
      |> form(~s(form[phx-submit="save"]), saved_search: %{name: "Renamed"})
      |> render_submit()

      assert_patch(view, "/searches")
      assert render(view) =~ "Renamed"
      assert %{name: "Renamed", query: "tag:elixir"} = reload(search)
    end

    test "cancel closes the form", %{conn: conn, user: user} do
      search = saved_search_fixture(user)
      {:ok, view, _html} = live(conn, "/searches/#{search.id}/edit")

      view |> element("a", "Cancel") |> render_click()

      assert_patch(view, "/searches")
      refute render(view) =~ "Edit saved search"
    end

    test "can't edit another user's search", %{conn: conn} do
      other = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
      search = saved_search_fixture(other)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, "/searches/#{search.id}/edit")
      end
    end
  end

  describe "Feeds" do
    test "publishes, rotates, and revokes a feed", %{conn: conn, user: user} do
      search = saved_search_fixture(user)
      {:ok, view, _html} = live(conn, "/searches")

      html = click(view, "enable_feed", search)
      first_token = reload(search).feed_token

      assert html =~ "Feed enabled."
      assert html =~ "Feed live"
      assert first_token
      assert has_element?(view, ~s(a[href="/feeds/#{first_token}.atom"]))

      html = click(view, "rotate_feed", search)
      second_token = reload(search).feed_token

      assert html =~ "Feed token rotated"
      assert second_token != first_token
      assert has_element?(view, ~s(a[href="/feeds/#{second_token}.atom"]))
      refute has_element?(view, ~s(a[href="/feeds/#{first_token}.atom"]))

      html = click(view, "disable_feed", search)

      assert html =~ "Feed revoked."
      refute html =~ "Feed live"
      assert reload(search).feed_token == nil
      assert has_element?(view, ~s(button[phx-click="enable_feed"]))
    end
  end

  describe "Delete" do
    test "deletes a search", %{conn: conn, user: user} do
      search = saved_search_fixture(user)
      {:ok, view, _html} = live(conn, "/searches")

      html = click(view, "delete", search)

      assert html =~ "Deleted."
      assert html =~ "No saved searches yet."
      assert Bookmarks.list_user_saved_searches(user.id) == []
    end

    test "can't delete or publish another user's search", %{conn: conn} do
      other = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
      search = saved_search_fixture(other)

      for event <- ["delete", "enable_feed", "disable_feed", "rotate_feed"] do
        {:ok, view, _html} = live(conn, "/searches")
        Process.flag(:trap_exit, true)
        catch_exit(render_hook(view, event, %{"id" => search.id}))
      end

      assert %{feed_token: nil} = reload(search)
    end
  end
end
