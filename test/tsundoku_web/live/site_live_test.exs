defmodule TsundokuWeb.SiteLiveTest do
  use TsundokuWeb.ConnCase

  use Oban.Testing, repo: Tsundoku.Repo

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Tsundoku.Bookmarks
  alias Tsundoku.Workers.EnrichMetadata
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

    test "shows saved metadata", %{conn: conn, user: user} do
      {:ok, tag} = Bookmarks.create_tag(%{name: "elixir", created_by_id: user.id})

      site =
        site_fixture(user, %{
          "url" => "https://blog.example.com/post",
          "display_name" => "A Post",
          "notes" => "my own notes",
          "tags" => [tag]
        })

      update_site(site,
        description: "fetched description",
        og_image_url: "https://blog.example.com/og.png",
        favicon_data: <<1, 2, 3>>,
        favicon_content_type: "image/png",
        crawl_status: "http_404",
        crawled_at: ~U[2026-01-02 03:04:05.000000Z]
      )

      conn = log_in_user(conn, user)
      {:ok, show_live, html} = live(conn, Routes.site_show_path(conn, :show, site))

      assert html =~ "A Post"
      assert html =~ "my own notes"
      assert html =~ "fetched description"
      assert html =~ ~s(src="https://blog.example.com/og.png")
      assert html =~ "data:image/png;base64,#{Base.encode64(<<1, 2, 3>>)}"
      assert html =~ "2026-01-02 03:04 UTC"
      assert html =~ "http_404"
      assert html =~ "https://web.archive.org/web/*/https://blog.example.com/post"
      assert html =~ "https://archive.ph/https://blog.example.com/post"

      assert has_element?(show_live, ~s(a[href="/sites?q=tag%3Aelixir"]), "elixir")

      assert has_element?(
               show_live,
               ~s(a[href="/sites?q=domain%3Ablog.example.com"]),
               "blog.example.com"
             )
    end

    test "falls back to the url as the title and shows placeholders", %{conn: conn, user: user} do
      site = site_fixture(user, %{"url" => "https://example.com/untitled"})

      conn = log_in_user(conn, user)
      {:ok, show_live, html} = live(conn, Routes.site_show_path(conn, :show, site))

      assert has_element?(show_live, "h2", "https://example.com/untitled")
      assert html =~ "No tags assigned."
      assert html =~ "—"
      refute html =~ "Notes"
      refute html =~ "Description"
    end

    test "re-fetch queues a metadata job", %{conn: conn, site: site, user: user} do
      conn = log_in_user(conn, user)
      {:ok, show_live, _html} = live(conn, Routes.site_show_path(conn, :show, site))

      before = length(all_enqueued(worker: EnrichMetadata, args: %{site_id: site.id}))

      assert show_live |> element("button", "Re-fetch") |> render_click() =~ "Re-fetch queued"

      assert length(all_enqueued(worker: EnrichMetadata, args: %{site_id: site.id})) ==
               before + 1
    end
  end

  describe "Index search" do
    setup %{conn: conn} do
      user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
      {:ok, tag} = Bookmarks.create_tag(%{name: "elixir", created_by_id: user.id})

      guide =
        site_fixture(user, %{
          "url" => "https://blog.example.com/elixir",
          "display_name" => "Elixir Guide",
          "tags" => [tag]
        })

      cooking =
        site_fixture(user, %{"url" => "https://food.test/recipes", "display_name" => "Cooking"})

      %{conn: log_in_user(conn, user), user: user, guide: guide, cooking: cooking}
    end

    defp pill?(view, type, value) do
      has_element?(
        view,
        ~s(button[phx-click="remove_filter"][phx-value-type="#{type}"][phx-value-value="#{value}"])
      )
    end

    defp type_query(view, text) do
      view |> form("#site-search-form", query_field: %{query: text}) |> render_change()
    end

    defp suggestion?(view, text) do
      has_element?(view, "#site-search-suggestions button", text)
    end

    test "shows everything with no filters", %{conn: conn} do
      {:ok, view, html} = live(conn, Routes.site_index_path(conn, :index))

      assert html =~ "2 saved bookmarks"
      assert html =~ "No filters."
      refute has_element?(view, "a", "Save")
    end

    test "filters by the q param and shows a pill and a save link", %{conn: conn} do
      {:ok, view, html} = live(conn, Routes.site_index_path(conn, :index, q: "tag:elixir"))

      assert html =~ "1 filtered bookmarks (of 2)"
      assert html =~ "Elixir Guide"
      refute html =~ "Cooking"
      assert pill?(view, "tag", "elixir")
      assert has_element?(view, "a", "Save")
    end

    test "submitting the search box turns typed text into filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index))

      typed =
        "foo title:bar tag:t domain:d.com url:u metadata:has status:404 " <>
          "-title:x -tag:y -domain:z.com -url:w"

      view |> form("#site-search-form", query_field: %{query: typed}) |> render_submit()

      assert_patch(
        view,
        Routes.site_index_path(conn, :index,
          page: 1,
          q:
            "title:foo title:bar tag:t domain:d.com url:u metadata:has status:http_404 " <>
              "-title:x -tag:y -domain:z.com -url:w"
        )
      )

      assert pill?(view, "title", "foo")
      assert pill?(view, "title", "bar")
      assert pill?(view, "tag", "t")
      assert pill?(view, "domain", "d.com")
      assert pill?(view, "url", "u")
      assert pill?(view, "metadata", "has")
      assert pill?(view, "status", "http_404")
      assert view |> element("#site-search-input") |> render() =~ ~s(value="")
    end

    test "submitting a blank search box changes nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index))

      html = view |> form("#site-search-form", query_field: %{query: "   "}) |> render_submit()

      assert html =~ "No filters."
      assert html =~ "2 saved bookmarks"
    end

    test "shows a metadata:missing pill", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index, q: "-metadata:has"))

      assert pill?(view, "metadata", "missing")
    end

    test "removing a pill drops that filter", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, Routes.site_index_path(conn, :index, q: "tag:elixir url:blog"))

      view
      |> element(~s(button[phx-click="remove_filter"][phx-value-type="tag"]))
      |> render_click()

      assert_patch(view, Routes.site_index_path(conn, :index, page: 1, q: "url:blog"))
      refute pill?(view, "tag", "elixir")
      assert pill?(view, "url", "blog")
    end

    test "suggests tags, domains, and field names as the user types", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index))

      type_query(view, "tag:el")
      assert suggestion?(view, "tag:elixir")

      type_query(view, "domain:blog")
      assert suggestion?(view, "domain:blog.example.com")

      type_query(view, "site:food")
      assert suggestion?(view, "site:food.test")

      type_query(view, "url:x")
      assert suggestion?(view, "url:")

      type_query(view, "ta")
      assert suggestion?(view, "tag:")

      type_query(view, "food")
      assert suggestion?(view, "domain:food.test")

      type_query(view, "cooking tag:el")
      assert suggestion?(view, "cooking tag:elixir")

      type_query(view, "")
      refute has_element?(view, "#site-search-suggestions")
    end

    test "clicking a suggestion applies it", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index))

      type_query(view, "tag:el")
      view |> element("#site-search-suggestions button", "tag:elixir") |> render_click()

      assert_patch(view, Routes.site_index_path(conn, :index, page: 1, q: "tag:elixir"))
      assert pill?(view, "tag", "elixir")
    end

    test "switches between alphabetical and recency sort", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index))

      view |> element(~s(button[phx-value-sort="alpha"])) |> render_click()
      assert_patch(view, Routes.site_index_path(conn, :index, page: 1, q: "", sort: "alpha"))

      html = render(view)
      {cooking_at, _} = :binary.match(html, "Cooking")
      {guide_at, _} = :binary.match(html, "Elixir Guide")
      assert cooking_at < guide_at

      view |> element(~s(button[phx-value-sort="recency"])) |> render_click()
      assert_patch(view, Routes.site_index_path(conn, :index, page: 1, q: ""))
    end

    test "keeps the sort when a filter is added", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index, sort: "alpha"))

      view |> element(~s(button[phx-click="add_filter_tag"]), "elixir") |> render_click()

      assert_patch(
        view,
        Routes.site_index_path(conn, :index, page: 1, q: "tag:elixir", sort: "alpha")
      )
    end

    test "clicking the same tag again doesn't stack duplicate filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index))

      for _ <- 1..3 do
        view |> element(~s(button[phx-click="add_filter_tag"]), "elixir") |> render_click()
      end

      assert_patch(view, Routes.site_index_path(conn, :index, page: 1, q: "tag:elixir"))

      html = render(view)
      assert length(Regex.scan(~r/phx-value-type="tag"/, html)) == 1
      assert html =~ "1 filtered bookmarks (of 2)"
    end

    test "typing a filter that's already applied changes nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index, q: "tag:elixir"))

      view
      |> form("#site-search-form", query_field: %{query: "tag:Elixir tag:elixir url:blog"})
      |> render_submit()

      assert_patch(view, Routes.site_index_path(conn, :index, page: 1, q: "tag:elixir url:blog"))
      assert length(Regex.scan(~r/phx-value-type="tag"/, render(view))) == 1
    end

    test "a row's domain link doesn't repeat a domain filter that's already applied", %{
      conn: conn,
      guide: guide
    } do
      {:ok, view, _html} =
        live(conn, Routes.site_index_path(conn, :index, q: "domain:blog.example.com"))

      assert has_element?(
               view,
               ~s(#site-#{guide.id} a[href="/sites?page=1&q=domain%3Ablog.example.com"]),
               "domain:blog.example.com"
             )
    end

    test "add_filter_tag from a tag picker only accepts the user's tags", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index, q: "url:example"))

      render_hook(view, "add_filter_tag", %{"filter_tag" => %{"tag" => "not-a-tag"}})
      assert pill?(view, "url", "example")
      refute pill?(view, "tag", "not-a-tag")

      render_hook(view, "add_filter_tag", %{"filter_tag" => %{"tag" => "elixir"}})

      assert_patch(
        view,
        Routes.site_index_path(conn, :index, page: 1, q: "url:example tag:elixir")
      )
    end

    test "accepts the legacy search and tags params", %{conn: conn} do
      {:ok, view, html} = live(conn, "/sites?search=guide&tags[]=elixir")
      assert html =~ "1 filtered bookmarks (of 2)"
      assert pill?(view, "tag", "elixir")

      {:ok, view, html} = live(conn, "/sites?tags[]=elixir")
      assert html =~ "1 filtered bookmarks (of 2)"
      assert pill?(view, "tag", "elixir")

      {:ok, _view, html} = live(conn, "/sites?search=cooking")
      assert html =~ "1 filtered bookmarks (of 2)"
      assert html =~ "Cooking"
    end

    test "shows favicon, description, domain, and crawl status on a row", %{
      conn: conn,
      guide: guide
    } do
      update_site(guide,
        description: "all about elixir",
        favicon_data: <<1, 2, 3>>,
        favicon_content_type: "image/png",
        crawl_status: "http_404"
      )

      {:ok, view, html} = live(conn, Routes.site_index_path(conn, :index))

      assert html =~ "all about elixir"
      assert html =~ "data:image/png;base64,#{Base.encode64(<<1, 2, 3>>)}"
      assert html =~ "https://web.archive.org/web/*/https://blog.example.com/elixir"
      assert has_element?(view, "#site-#{guide.id} a", "domain:blog.example.com")
      assert has_element?(view, "#site-#{guide.id} a", "status:http_404")
    end

    test "uses the url as the title when a site has none", %{conn: conn, user: user} do
      untitled = site_fixture(user, %{"url" => "https://example.com/untitled"})

      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :index))

      assert has_element?(
               view,
               ~s(#site-#{untitled.id} a[href="https://example.com/untitled"]),
               "https://example.com/untitled"
             )
    end

    test "picks up bookmarks saved elsewhere after the debounce", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, Routes.site_index_path(conn, :index, sort: "alpha"))
      refute html =~ "Saved From The Extension"

      site_fixture(user, %{
        "url" => "https://example.com/elsewhere",
        "display_name" => "Saved From The Extension"
      })

      # LiveHelpers debounce is 500ms; give it a bit of slack.
      Process.sleep(700)

      html = render(view)
      assert html =~ "Saved From The Extension"
      assert html =~ "3 saved bookmarks"
    end
  end

  describe "Index pagination" do
    setup %{conn: conn} do
      user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)

      for n <- 1..51 do
        site_fixture(user, %{"url" => "https://example.com/#{n}", "display_name" => "site #{n}"})
      end

      %{conn: log_in_user(conn, user)}
    end

    defp row_count(view) do
      length(Regex.scan(~r/id="site-[0-9a-f]{8}-/, render(view)))
    end

    test "pages through results", %{conn: conn} do
      {:ok, view, html} = live(conn, Routes.site_index_path(conn, :index))

      assert html =~ "51 saved bookmarks"
      assert row_count(view) == 50

      view |> element(~s(a[phx-click="nav"]), "Next") |> render_click()
      assert_patch(view, Routes.site_index_path(conn, :index, page: 2, q: ""))
      assert row_count(view) == 1

      view |> element(~s(a[phx-click="nav"]), "Previous") |> render_click()
      assert_patch(view, Routes.site_index_path(conn, :index, page: 1, q: ""))
      assert row_count(view) == 50

      view |> element(~s(a[phx-click="nav"][phx-value-page="2"]), "2") |> render_click()
      assert_patch(view, Routes.site_index_path(conn, :index, page: 2, q: ""))
    end
  end

  describe "Site form" do
    setup %{conn: conn} do
      user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
      %{conn: log_in_user(conn, user), user: user}
    end

    defp type_tag(view, name) do
      view
      |> element(~s(#site-form input[phx-keyup="create_tag_input"]))
      |> render_keyup(%{"value" => name})
    end

    defp click_add_tag(view), do: view |> element("#site-form a", "Add tag") |> render_click()

    defp tag_chip_count(view) do
      view |> render() |> String.split(~s(phx-click="remove_tag")) |> length() |> Kernel.-(1)
    end

    defp saved_tag_names(user, url) do
      url
      |> Bookmarks.get_user_bookmark_by_url(user.id)
      |> Tsundoku.Repo.preload(:tags)
      |> Map.get(:tags)
      |> Enum.map(& &1.name)
    end

    test "creates a new tag and saves it with the site", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :new))

      type_tag(view, "fresh")
      assert click_add_tag(view) =~ "fresh"
      assert tag_chip_count(view) == 1

      {:ok, _, _html} =
        view
        |> form("#site-form", site: %{url: "https://example.com/tagged", display_name: "Tagged"})
        |> render_submit()
        |> follow_redirect(conn, Routes.site_index_path(conn, :index))

      assert saved_tag_names(user, "https://example.com/tagged") == ["fresh"]
    end

    test "reuses an existing tag instead of creating a duplicate", %{conn: conn, user: user} do
      {:ok, _} = Bookmarks.create_tag(%{name: "elixir", created_by_id: user.id})
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :new))

      type_tag(view, " elixir ")
      click_add_tag(view)

      assert tag_chip_count(view) == 1
      assert length(Bookmarks.list_user_tags(user.id)) == 1
    end

    test "ignores a blank tag", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :new))

      type_tag(view, "   ")
      assert click_add_tag(view) =~ "No tags."
      assert Bookmarks.list_user_tags(user.id) == []
    end

    test "doesn't add a tag the site already has", %{conn: conn, user: user} do
      {:ok, tag} = Bookmarks.create_tag(%{name: "elixir", created_by_id: user.id})
      site = site_fixture(user, %{"url" => "https://example.com/has-tag", "tags" => [tag]})

      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :edit, site))
      assert tag_chip_count(view) == 1

      type_tag(view, "elixir")
      click_add_tag(view)

      assert tag_chip_count(view) == 1
    end

    test "removes a tag from the site", %{conn: conn, user: user} do
      {:ok, tag} = Bookmarks.create_tag(%{name: "elixir", created_by_id: user.id})
      site = site_fixture(user, %{"url" => "https://example.com/has-tag", "tags" => [tag]})

      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :edit, site))

      assert view |> element(~s(button[phx-click="remove_tag"])) |> render_click() =~ "No tags."

      {:ok, _, _html} =
        view
        |> form("#site-form", site: %{display_name: "Untagged"})
        |> render_submit()
        |> follow_redirect(conn, Routes.site_index_path(conn, :index))

      assert saved_tag_names(user, "https://example.com/has-tag") == []
      assert Bookmarks.get_tag(tag.id)
    end

    test "shows errors when saving a new site fails", %{conn: conn, user: user} do
      site_fixture(user, %{"url" => "https://example.com/taken"})
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :new))

      assert view |> form("#site-form", site: %{url: "not a url"}) |> render_submit() =~
               "Invalid URL"

      assert view
             |> form("#site-form", site: %{url: "https://example.com/taken"})
             |> render_submit() =~ "you already have a bookmark at this URL"
    end

    test "shows errors when saving an edit fails", %{conn: conn, user: user} do
      site = site_fixture(user, %{"url" => "https://example.com/editable"})
      {:ok, view, _html} = live(conn, Routes.site_index_path(conn, :edit, site))

      assert view |> form("#site-form", site: %{url: "not a url"}) |> render_submit() =~
               "Invalid URL"

      assert Bookmarks.get_site!(site.id).url == "https://example.com/editable"
    end
  end

  defp site_fixture(user, attrs) do
    {:ok, site} =
      %{"created_by_id" => user.id, "tags" => []}
      |> Map.merge(attrs)
      |> Bookmarks.create_site()

    site
  end

  # Sets fields the crawler normally fills in.
  defp update_site(site, fields) do
    Tsundoku.Repo.update_all(from(s in Tsundoku.Bookmarks.Site, where: s.id == ^site.id),
      set: fields
    )
  end
end
