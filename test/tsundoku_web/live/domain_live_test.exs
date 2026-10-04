defmodule TsundokuWeb.DomainLiveTest do
  use TsundokuWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Tsundoku.Bookmarks

  describe "Index" do
    test "lists bookmark domains with tag counts", %{conn: conn} do
      user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
      {:ok, tag} = Bookmarks.create_tag(%{name: "elixir", created_by_id: user.id})

      {:ok, _site} =
        Bookmarks.create_site(%{
          "url" => "https://www.example.com/articles",
          "display_name" => "Example articles",
          "created_by_id" => user.id,
          "tags" => [tag]
        })

      conn = log_in_user(conn, user)
      {:ok, _index_live, html} = live(conn, Routes.domain_index_path(conn, :index))

      assert html =~ "Domains"
      assert html =~ "example.com"
      assert html =~ "1 bookmark"
      assert html =~ "elixir"
    end
  end

  describe "Index search and sort" do
    setup %{conn: conn} do
      user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
      {:ok, tag} = Bookmarks.create_tag(%{name: "elixir", created_by_id: user.id})

      site_fixture(user, "https://zebra.test/1", [tag])
      site_fixture(user, "https://zebra.test/2", [tag])
      site_fixture(user, "https://apple.test/1", [])

      %{conn: log_in_user(conn, user), user: user}
    end

    defp domain_order(view) do
      ~r/id="domain-([^"]+\.test)"/ |> Regex.scan(render(view)) |> Enum.map(&List.last/1)
    end

    test "orders by bookmark count by default", %{conn: conn} do
      {:ok, view, html} = live(conn, Routes.domain_index_path(conn, :index))

      assert html =~ "2 bookmark domains"
      assert html =~ "2 bookmarks"
      assert html =~ "No tags assigned."
      assert domain_order(view) == ["zebra.test", "apple.test"]

      assert has_element?(
               view,
               ~s(a[href="/sites?q=domain%3Azebra.test+tag%3Aelixir"]),
               "elixir"
             )
    end

    test "switches between alphabetical and count sort", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.domain_index_path(conn, :index))

      view |> element(~s(button[phx-value-sort="alpha"])) |> render_click()

      assert_patch(
        view,
        Routes.domain_index_path(conn, :index, page: 1, search: "", sort: "alpha")
      )

      assert domain_order(view) == ["apple.test", "zebra.test"]

      view |> element(~s(button[phx-value-sort="count"])) |> render_click()
      assert_patch(view, Routes.domain_index_path(conn, :index, page: 1, search: ""))
      assert domain_order(view) == ["zebra.test", "apple.test"]
    end

    test "filters by search text and keeps the sort", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.domain_index_path(conn, :index, sort: "alpha"))

      view |> form("#domain-search-form", query_field: %{query: " zeb "}) |> render_change()

      assert_patch(
        view,
        Routes.domain_index_path(conn, :index, page: 1, search: "zeb", sort: "alpha")
      )

      assert domain_order(view) == ["zebra.test"]
      assert render(view) =~ "1 bookmark domains"
    end

    test "says so when nothing matches", %{conn: conn} do
      {:ok, _view, html} = live(conn, Routes.domain_index_path(conn, :index, search: "nope"))

      assert html =~ "No domains match &quot;nope&quot;."
    end

    test "falls back to page 1 for a junk page param", %{conn: conn} do
      for page <- ["abc", "0", "-2"] do
        {:ok, view, _html} = live(conn, Routes.domain_index_path(conn, :index, page: page))

        assert domain_order(view) == ["zebra.test", "apple.test"]
      end
    end

    test "picks up bookmarks saved elsewhere after the debounce", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, Routes.domain_index_path(conn, :index, sort: "alpha"))

      site_fixture(user, "https://mango.test/1", [])

      # LiveHelpers debounce is 500ms; give it a bit of slack.
      Process.sleep(700)

      assert domain_order(view) == ["apple.test", "mango.test", "zebra.test"]
      assert render(view) =~ "3 bookmark domains"
    end
  end

  describe "Index with no bookmarks" do
    test "shows an empty state", %{conn: conn} do
      user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, Routes.domain_index_path(conn, :index))

      assert html =~ "No bookmark domains found."
    end
  end

  describe "Index pagination" do
    test "pages through domains", %{conn: conn} do
      user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)

      for n <- 1..51 do
        site_fixture(user, "https://d#{String.pad_leading("#{n}", 2, "0")}.test/", [])
      end

      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, Routes.domain_index_path(conn, :index, sort: "alpha"))

      assert html =~ "51 bookmark domains"
      assert length(domain_order(view)) == 50

      view |> element(~s(a[phx-click="nav"]), "Next") |> render_click()

      assert_patch(
        view,
        Routes.domain_index_path(conn, :index, page: 2, search: "", sort: "alpha")
      )

      assert domain_order(view) == ["d51.test"]

      view |> element(~s(a[phx-click="nav"]), "Previous") |> render_click()

      assert_patch(
        view,
        Routes.domain_index_path(conn, :index, page: 1, search: "", sort: "alpha")
      )

      assert length(domain_order(view)) == 50
    end
  end

  defp site_fixture(user, url, tags) do
    {:ok, site} =
      Bookmarks.create_site(%{"url" => url, "created_by_id" => user.id, "tags" => tags})

    site
  end
end
