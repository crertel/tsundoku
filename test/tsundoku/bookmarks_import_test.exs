defmodule Tsundoku.BookmarksImportTest do
  use Tsundoku.DataCase, async: true
  use Oban.Testing, repo: Tsundoku.Repo

  alias Tsundoku.AccountsFixtures
  alias Tsundoku.Bookmarks
  alias Tsundoku.Workers.EnrichMetadata

  # Parses `html` as a bookmarks export and returns `{tags, links}` with
  # the links sorted by url.
  defp import_html(html) do
    path = Path.join(System.tmp_dir!(), "bookmarks_#{System.unique_integer([:positive])}.html")
    File.write!(path, html)
    on_exit(fn -> File.rm(path) end)

    {:ok, tags, links} = Bookmarks.import_from_file(path)
    {Enum.sort(tags), Enum.sort_by(links, fn {_tags, url, _title} -> url end)}
  end

  describe "import_from_file/1" do
    test "tags each link with the folders it sits in" do
      {tags, links} =
        import_html("""
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks Menu</H1>
        <DL><p>
          <DT><H3 ADD_DATE="1">Outer</H3>
          <DL><p>
            <DT><A HREF="https://example.com/1" ADD_DATE="1">One</A>
            <DT><H3>Inner</H3>
            <DL><p>
              <DT><A HREF="https://example.com/2">Two</A>
            </DL><p>
            <DT><A HREF="https://example.com/3">Three</A>
          </DL><p>
          <DT><H3>Sibling</H3>
          <DL><p>
            <DT><A HREF="https://example.com/4">Four</A>
          </DL><p>
          <DT><A HREF="https://example.com/5">Five</A>
        </DL><p>
        """)

      assert tags == ["Inner", "Outer", "Sibling"]

      assert links == [
               {["Outer"], "https://example.com/1", "One"},
               {["Inner", "Outer"], "https://example.com/2", "Two"},
               {["Outer"], "https://example.com/3", "Three"},
               {["Sibling"], "https://example.com/4", "Four"},
               {[], "https://example.com/5", "Five"}
             ]
    end

    test "skips description lines" do
      {_tags, links} =
        import_html("""
        <DL><p>
          <DT><A HREF="https://example.com/a">A</A>
          <DD>a description of A
          <DT><A HREF="https://example.com/b">B</A>
        </DL><p>
        """)

      assert links == [
               {[], "https://example.com/a", "A"},
               {[], "https://example.com/b", "B"}
             ]
    end

    test "keeps links with an empty title or markup in the title" do
      {_tags, links} =
        import_html("""
        <DL><p>
          <DT><A HREF="https://example.com/empty"></A>
          <DT><A HREF="https://example.com/markup"><b>Bold</b> title</A>
        </DL><p>
        """)

      assert links == [
               {[], "https://example.com/empty", ""},
               {[], "https://example.com/markup", "Bold title"}
             ]
    end

    test "skips anchors without an href and empty folders" do
      {tags, links} =
        import_html("""
        <DL><p>
          <DT><A NAME="anchor">Not a link</A>
          <DT><H3>Empty</H3>
          <DL><p>
          </DL><p>
          <DT><A HREF="https://example.com/a">A</A>
        </DL><p>
        """)

      assert tags == []
      assert links == [{[], "https://example.com/a", "A"}]
    end

    test "drops entries that aren't web pages" do
      {tags, links} =
        import_html("""
        <DL><p>
          <DT><H3>Toolbar</H3>
          <DL><p>
            <DT><A HREF="place:sort=8">Most Visited</A>
            <DT><A HREF="javascript:alert(1)">Bookmarklet</A>
            <DT><A HREF="file:///home/me/notes.html">Local file</A>
            <DT><A HREF="http://">No host</A>
            <DT><A HREF="https://example.com/a">A</A>
            <DT><A HREF="HTTP://example.com/b">B</A>
          </DL><p>
        </DL><p>
        """)

      assert tags == ["Toolbar"]

      assert links == [
               {["Toolbar"], "HTTP://example.com/b", "B"},
               {["Toolbar"], "https://example.com/a", "A"}
             ]
    end

    test "returns nothing for a file with no bookmarks" do
      assert import_html("<html><body>not a bookmarks file</body></html>") == {[], []}
    end
  end

  describe "bulk_insert_imported/4" do
    test "saves web urls with their tags, queues a crawl for each, and skips the rest" do
      user = AccountsFixtures.user_fixture()

      records = [
        %{"tags" => ["reading"], "url" => "https://example.com/a", "title" => "A"},
        %{"tags" => [], "url" => "javascript:alert(1)", "title" => "Bookmarklet"},
        %{"tags" => [], "url" => "place:sort=8", "title" => "Most Visited"},
        %{"tags" => [], "url" => "", "title" => "Blank"},
        %{"tags" => [], "url" => nil, "title" => "Missing"}
      ]

      assert Bookmarks.bulk_insert_imported(["reading"], records, user.id) ==
               %{sites_inserted: 1, tags_inserted: 1}

      assert [site] = Bookmarks.search_sites(user.id, Bookmarks.parse_site_query("")).entries
      assert site.url == "https://example.com/a"
      assert site.display_name == "A"
      assert site.domain == "example.com"
      assert Enum.map(site.tags, & &1.name) == ["reading"]

      assert [%{args: %{"site_id" => site_id}}] = all_enqueued(worker: EnrichMetadata)
      assert site_id == site.id
    end

    test "leaves existing bookmarks alone and reports progress" do
      user = AccountsFixtures.user_fixture()

      {:ok, existing} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/a",
          "display_name" => "Mine",
          "created_by_id" => user.id,
          "tags" => []
        })

      records = [
        %{"tags" => ["new"], "url" => "https://example.com/a", "title" => "Theirs"},
        %{"tags" => ["new"], "url" => "https://example.com/b", "title" => "B"}
      ]

      test_pid = self()
      progress = fn update -> send(test_pid, {:progress, update}) end

      assert Bookmarks.bulk_insert_imported(["new"], records, user.id, progress) ==
               %{sites_inserted: 1, tags_inserted: 1}

      assert Bookmarks.get_site!(existing.id).display_name == "Mine"
      assert Bookmarks.count_user_sites(user.id) == 2

      assert_received {:progress, %{processed: 0, stage: :sites}}
      assert_received {:progress, %{processed: 2, stage: :sites}}
    end
  end
end
