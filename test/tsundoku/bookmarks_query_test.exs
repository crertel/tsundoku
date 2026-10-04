defmodule Tsundoku.BookmarksQueryTest do
  use Tsundoku.DataCase, async: true

  alias Tsundoku.AccountsFixtures
  alias Tsundoku.Bookmarks
  alias Tsundoku.Bookmarks.Site

  defp site_fixture(user, attrs) do
    {:ok, site} =
      %{"created_by_id" => user.id, "tags" => []}
      |> Map.merge(attrs)
      |> Bookmarks.create_site()

    site
  end

  defp tag_fixture(user, name) do
    {:ok, tag} = Bookmarks.create_tag(%{"name" => name, "created_by_id" => user.id})
    tag
  end

  defp search(user, query, opts \\ []) do
    Bookmarks.search_sites(user.id, Bookmarks.parse_site_query(query), opts)
  end

  defp names(page), do: page.entries |> Enum.map(& &1.display_name) |> Enum.sort()

  describe "parse_site_query/1" do
    test "collects negated filters separately" do
      parsed =
        Bookmarks.parse_site_query("-tag:Foo -domain:www.Example.com -url:ABC -title:bad keep")

      assert parsed.exclude_tags == ["foo"]
      assert parsed.exclude_domains == ["example.com"]
      assert parsed.exclude_urls == ["abc"]
      assert parsed.exclude_titles == ["bad"]
      assert parsed.bare_phrase == "keep"
      assert parsed.tags == []
    end

    test "normalizes status values" do
      assert Bookmarks.parse_site_query("status:404").crawl_status == "http_404"
      assert Bookmarks.parse_site_query("status:Failed").crawl_status == "failed"
      assert Bookmarks.parse_site_query("status:OK").crawl_status == "ok"
      assert Bookmarks.parse_site_query("no status here").crawl_status == nil
    end

    test "inverts negated metadata filters and ignores unknown values" do
      assert Bookmarks.parse_site_query("-metadata:has").has_metadata == false
      assert Bookmarks.parse_site_query("-metadata:missing").has_metadata == true
      assert Bookmarks.parse_site_query("metadata:bogus").has_metadata == nil
    end

    test "ignores fielded tokens with empty values" do
      parsed = Bookmarks.parse_site_query(~s(tag:"" url:"" hello))

      assert parsed.tags == []
      assert parsed.urls == []
      assert parsed.bare_phrase == "hello"
    end

    test "matches field names in any case" do
      parsed =
        Bookmarks.parse_site_query(
          ~s(Tag:Elixir DOMAIN:Example.com Site:other.test URL:Blog Title:"Two Words" ) <>
            "Metadata:has STATUS:404 -TAG:Rust"
        )

      assert parsed.tags == ["elixir"]
      assert parsed.domains == ["example.com", "other.test"]
      assert parsed.urls == ["blog"]
      assert parsed.titles == ["Two Words"]
      assert parsed.has_metadata == true
      assert parsed.crawl_status == "http_404"
      assert parsed.exclude_tags == ["rust"]
      assert parsed.bare_phrase == ""
    end

    test "keeps quoted text that looks like a field as title text" do
      parsed = Bookmarks.parse_site_query(~s("URL:foo" notafield:bar))

      assert parsed.urls == []
      assert parsed.bare_phrase == "URL:foo notafield:bar"
    end

    test "treats a nil or blank query as no filters" do
      for query <- [nil, "", "   "] do
        parsed = Bookmarks.parse_site_query(query)

        assert parsed.bare_phrase == ""
        assert parsed.tags == []
        assert parsed.has_metadata == nil
      end
    end
  end

  describe "query_fragment/2" do
    test "leaves simple values bare" do
      assert Bookmarks.query_fragment("tag", "elixir") == "tag:elixir"
      assert Bookmarks.query_fragment("domain", :example) == "domain:example"
    end

    test "quotes values with whitespace or quotes" do
      assert Bookmarks.query_fragment("tag", "two words") == ~s(tag:"two words")
      assert Bookmarks.query_fragment("tag", ~s(a"b)) == ~s(tag:"a\\"b")
    end
  end

  describe "remove_filter/3" do
    test "removes the first matching tag, case-insensitively" do
      assert Bookmarks.remove_filter("tag:a tag:b foo", "tag", "A") == "tag:b foo"
      assert Bookmarks.remove_filter("tag:a tag:a", "tag", "a") == "tag:a"
    end

    test "removes filters whose field name is in another case" do
      assert Bookmarks.remove_filter("Tag:a url:b", "tag", "a") == "url:b"
      assert Bookmarks.remove_filter("TITLE:hello tag:a", "title", "hello") == "tag:a"
      assert Bookmarks.remove_filter("Status:404 foo", "status", "http_404") == "foo"
      assert Bookmarks.remove_filter("hello Metadata:has", "title", "hello") == "metadata:has"
    end

    test "removes quoted values" do
      assert Bookmarks.remove_filter(~s(url:"a b" tag:c), "url", "a b") == "tag:c"
    end

    test "treats site: as an alias for domain:" do
      assert Bookmarks.remove_filter("site:example.com x", "domain", "example.com") == "x"
      assert Bookmarks.remove_filter("domain:example.com x", "domain", "example.com") == "x"
    end

    test "leaves negated and non-matching filters alone" do
      assert Bookmarks.remove_filter("-tag:a tag:a", "tag", "a") == "-tag:a"
      assert Bookmarks.remove_filter("tag:a url:a", "tag", "b") == "tag:a url:a"
      assert Bookmarks.remove_filter("url:a tag:b", "tag", "a") == "url:a tag:b"
    end

    test "removes every metadata or status token regardless of value" do
      assert Bookmarks.remove_filter("foo metadata:has -metadata:x", "metadata", "") == "foo"
      assert Bookmarks.remove_filter("status:404 foo", "status", "anything") == "foo"
    end

    test "removes a title: token" do
      assert Bookmarks.remove_filter("title:hello tag:a", "title", "Hello") == "tag:a"

      assert Bookmarks.remove_filter(~s(title:"hello world" tag:a), "title", "hello world") ==
               "tag:a"
    end

    test "removes the bare phrase when no title: token matches" do
      assert Bookmarks.remove_filter("hello tag:a world", "title", "hello world") == "tag:a"
    end

    test "removes the bare phrase alongside metadata and status filters" do
      assert Bookmarks.remove_filter("hello metadata:has status:ok", "title", "hello") ==
               "metadata:has status:ok"
    end

    test "leaves the query alone when the title doesn't match" do
      assert Bookmarks.remove_filter("hello tag:a", "title", "other") == "hello tag:a"
    end
  end

  describe "search_sites/3 exclusions" do
    setup do
      user = AccountsFixtures.user_fixture()
      elixir = tag_fixture(user, "elixir")

      site_fixture(user, %{
        "display_name" => "Elixir Guide",
        "url" => "https://blog.example.com/elixir",
        "tags" => [elixir]
      })

      site_fixture(user, %{
        "display_name" => "Cooking Recipes",
        "url" => "https://food.test/recipes"
      })

      %{user: user}
    end

    test "-tag: drops tagged sites", %{user: user} do
      assert names(search(user, "-tag:elixir")) == ["Cooking Recipes"]
    end

    test "-domain: drops the domain and its subdomains", %{user: user} do
      assert names(search(user, "-domain:example.com")) == ["Cooking Recipes"]
    end

    test "-url: drops matching urls", %{user: user} do
      assert names(search(user, "-url:recipes")) == ["Elixir Guide"]
    end

    test "-title: drops matching titles", %{user: user} do
      assert names(search(user, "-title:elixir")) == ["Cooking Recipes"]
    end
  end

  describe "search_sites/3 domain and url matching" do
    setup do
      %{user: AccountsFixtures.user_fixture()}
    end

    test "domain: matches subdomains but not lookalike hosts", %{user: user} do
      site_fixture(user, %{"display_name" => "apex", "url" => "https://example.com/a"})
      site_fixture(user, %{"display_name" => "sub", "url" => "https://blog.example.com/b"})
      site_fixture(user, %{"display_name" => "lookalike", "url" => "https://notexample.com/c"})

      assert names(search(user, "domain:example.com")) == ["apex", "sub"]
    end

    test "url: treats LIKE wildcards literally", %{user: user} do
      site_fixture(user, %{"display_name" => "literal", "url" => "https://example.com/a_b"})
      site_fixture(user, %{"display_name" => "other", "url" => "https://example.com/axb"})

      assert names(search(user, "url:a_b")) == ["literal"]
    end

    test "only returns the given user's sites", %{user: user} do
      other = AccountsFixtures.user_fixture()
      site_fixture(user, %{"display_name" => "mine", "url" => "https://example.com/mine"})
      site_fixture(other, %{"display_name" => "theirs", "url" => "https://example.com/theirs"})

      assert names(search(user, "")) == ["mine"]
    end
  end

  describe "search_sites/3 status filter" do
    setup do
      user = AccountsFixtures.user_fixture()

      for {name, status} <- [{"ok", "ok"}, {"gone", "http_404"}, {"slow", "timeout"}] do
        site =
          site_fixture(user, %{"display_name" => name, "url" => "https://example.com/#{name}"})

        Repo.update_all(from(s in Site, where: s.id == ^site.id), set: [crawl_status: status])
      end

      site_fixture(user, %{"display_name" => "uncrawled", "url" => "https://example.com/new"})

      %{user: user}
    end

    test "status:<code> matches that http status", %{user: user} do
      assert names(search(user, "status:404")) == ["gone"]
    end

    test "status:ok matches successful crawls", %{user: user} do
      assert names(search(user, "status:ok")) == ["ok"]
    end

    test "status:failed matches every crawled-but-not-ok site", %{user: user} do
      assert names(search(user, "status:failed")) == ["gone", "slow"]
    end
  end

  describe "search_sites/3 sorting and pagination" do
    setup do
      user = AccountsFixtures.user_fixture()

      for name <- ["charlie", "alpha", "bravo"] do
        site_fixture(user, %{"display_name" => name, "url" => "https://example.com/#{name}"})
      end

      %{user: user}
    end

    test "sort: :alpha orders by title", %{user: user} do
      page = search(user, "", sort: :alpha)

      assert Enum.map(page.entries, & &1.display_name) == ["alpha", "bravo", "charlie"]
    end

    test "paginates", %{user: user} do
      first = search(user, "", sort: :alpha, page_size: 2)

      assert Enum.map(first.entries, & &1.display_name) == ["alpha", "bravo"]
      assert first.page_number == 1
      assert first.total_entries == 3
      assert first.total_pages == 2

      second = search(user, "", sort: :alpha, page_size: 2, page: 2)

      assert Enum.map(second.entries, & &1.display_name) == ["charlie"]
      assert second.page_number == 2
    end

    test "accepts the page as a string and falls back to page 1 on junk", %{user: user} do
      assert search(user, "", page_size: 2, page: "2").page_number == 2

      for junk <- ["nope", "0", "-3", 0, nil] do
        assert search(user, "", page_size: 2, page: junk).page_number == 1
      end
    end

    test "reports zero pages when nothing matches", %{user: user} do
      page = search(user, "url:nothing-like-this")

      assert page.entries == []
      assert page.total_entries == 0
      assert page.total_pages == 0
    end
  end
end
