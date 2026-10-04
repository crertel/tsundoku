defmodule Tsundoku.BookmarksBackupTest do
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

  defp tag_fixture(user, attrs) do
    {:ok, tag} = attrs |> Map.put("created_by_id", user.id) |> Bookmarks.create_tag()
    tag
  end

  defp user_site(user, url) do
    url |> Bookmarks.get_user_bookmark_by_url(user.id) |> Repo.preload(:tags)
  end

  defp tag_names(site), do: site.tags |> Enum.map(& &1.name) |> Enum.sort()

  # A user with two tags and two sites, one of them crawled.
  defp populated_user do
    user = AccountsFixtures.user_fixture()
    elixir = tag_fixture(user, %{"name" => "elixir", "description" => "the language"})
    web = tag_fixture(user, %{"name" => "web"})

    crawled =
      site_fixture(user, %{
        "url" => "https://example.com/crawled",
        "display_name" => "Crawled",
        "notes" => "my notes",
        "tags" => [elixir, web]
      })

    Repo.update_all(from(s in Site, where: s.id == ^crawled.id),
      set: [
        description: "a description",
        favicon_url: "https://example.com/favicon.ico",
        favicon_data: <<1, 2, 3>>,
        favicon_content_type: "image/x-icon",
        og_image_url: "https://example.com/og.png",
        crawled_at: ~U[2026-01-02 03:04:05.000000Z],
        crawl_status: "ok"
      ]
    )

    site_fixture(user, %{"url" => "https://example.com/plain", "display_name" => "Plain"})

    user
  end

  describe "export_user/1" do
    test "dumps the user's tags and sites" do
      user = populated_user()

      dump = Bookmarks.export_user(user)

      assert dump.version == 1
      assert dump.user_email == user.email
      assert {:ok, _, _} = DateTime.from_iso8601(dump.exported_at)

      assert dump.tags == [
               %{name: "elixir", description: "the language"},
               %{name: "web", description: nil}
             ]

      assert [crawled] = Enum.filter(dump.sites, &(&1.url == "https://example.com/crawled"))
      assert crawled.display_name == "Crawled"
      assert crawled.notes == "my notes"
      assert crawled.description == "a description"
      assert crawled.favicon_url == "https://example.com/favicon.ico"
      assert crawled.favicon_data_b64 == Base.encode64(<<1, 2, 3>>)
      assert crawled.favicon_content_type == "image/x-icon"
      assert crawled.og_image_url == "https://example.com/og.png"
      assert crawled.crawled_at == "2026-01-02T03:04:05.000000Z"
      assert crawled.crawl_status == "ok"
      assert Enum.sort(crawled.tags) == ["elixir", "web"]

      assert [plain] = Enum.filter(dump.sites, &(&1.url == "https://example.com/plain"))
      assert plain.favicon_data_b64 == nil
      assert plain.crawled_at == nil
      assert plain.tags == []
    end

    test "leaves out other users' data" do
      user = populated_user()
      other = AccountsFixtures.user_fixture()
      tag_fixture(other, %{"name" => "theirs"})
      site_fixture(other, %{"url" => "https://example.com/theirs"})

      dump = Bookmarks.export_user(user)

      assert length(dump.sites) == 2
      assert Enum.map(dump.tags, & &1.name) == ["elixir", "web"]
    end

    test "is empty for a user with no data" do
      dump = Bookmarks.export_user(AccountsFixtures.user_fixture())

      assert dump.tags == []
      assert dump.sites == []
    end
  end

  describe "restore_user/2" do
    test "round-trips an export through JSON into another account" do
      dump = populated_user() |> Bookmarks.export_user() |> Jason.encode!() |> Jason.decode!()
      target = AccountsFixtures.user_fixture()

      assert Bookmarks.restore_user(target, dump) ==
               {:ok, %{tags_created: 2, sites_created: 2, sites_skipped: 0}}

      crawled = user_site(target, "https://example.com/crawled")
      assert crawled.display_name == "Crawled"
      assert crawled.notes == "my notes"
      assert crawled.description == "a description"
      assert crawled.favicon_data == <<1, 2, 3>>
      assert crawled.favicon_content_type == "image/x-icon"
      assert crawled.og_image_url == "https://example.com/og.png"
      assert crawled.crawled_at == ~U[2026-01-02 03:04:05.000000Z]
      assert crawled.crawl_status == "ok"
      assert crawled.domain == "example.com"
      assert tag_names(crawled) == ["elixir", "web"]

      assert tag_names(user_site(target, "https://example.com/plain")) == []

      assert Bookmarks.get_user_tag_by_name("elixir", target.id).description == "the language"
    end

    test "accepts the atom-keyed map export_user/1 returns" do
      dump = Bookmarks.export_user(populated_user())
      target = AccountsFixtures.user_fixture()

      assert {:ok, %{tags_created: 2, sites_created: 2, sites_skipped: 0}} =
               Bookmarks.restore_user(target, dump)

      assert tag_names(user_site(target, "https://example.com/crawled")) == ["elixir", "web"]
    end

    test "is idempotent" do
      user = populated_user()
      dump = Bookmarks.export_user(user)

      assert Bookmarks.restore_user(user, dump) ==
               {:ok, %{tags_created: 0, sites_created: 0, sites_skipped: 2}}

      assert Bookmarks.count_user_sites(user.id) == 2
      assert length(Bookmarks.list_user_tags(user.id)) == 2
    end

    test "keeps an existing site and unions its tags with the dump's" do
      target = AccountsFixtures.user_fixture()
      mine = tag_fixture(target, %{"name" => "mine"})

      site_fixture(target, %{
        "url" => "https://example.com/crawled",
        "display_name" => "My Own Title",
        "tags" => [mine]
      })

      dump = Bookmarks.export_user(populated_user())

      assert Bookmarks.restore_user(target, dump) ==
               {:ok, %{tags_created: 2, sites_created: 1, sites_skipped: 1}}

      existing = user_site(target, "https://example.com/crawled")
      assert existing.display_name == "My Own Title"
      assert existing.notes == nil
      assert tag_names(existing) == ["elixir", "mine", "web"]
    end

    test "doesn't touch other users' data" do
      source = populated_user()
      target = AccountsFixtures.user_fixture()

      {:ok, _} = Bookmarks.restore_user(target, Bookmarks.export_user(source))

      assert Bookmarks.count_user_sites(source.id) == 2
      assert tag_names(user_site(source, "https://example.com/crawled")) == ["elixir", "web"]
    end

    test "drops site tags the dump doesn't define" do
      target = AccountsFixtures.user_fixture()

      dump = %{
        "version" => 1,
        "tags" => [%{"name" => "known"}],
        "sites" => [%{"url" => "https://example.com/x", "tags" => ["known", "unknown"]}]
      }

      assert {:ok, %{tags_created: 1, sites_created: 1}} = Bookmarks.restore_user(target, dump)
      assert tag_names(user_site(target, "https://example.com/x")) == ["known"]
    end

    test "ignores favicon data that isn't valid base64" do
      target = AccountsFixtures.user_fixture()

      dump = %{
        "version" => "1",
        "sites" => [%{"url" => "https://example.com/x", "favicon_data_b64" => "not base64!"}]
      }

      assert {:ok, %{sites_created: 1}} = Bookmarks.restore_user(target, dump)
      assert user_site(target, "https://example.com/x").favicon_data == nil
    end

    test "rejects unsupported versions" do
      target = AccountsFixtures.user_fixture()

      assert Bookmarks.restore_user(target, %{"version" => 2, "sites" => []}) ==
               {:error, {:unsupported_version, 2}}

      assert Bookmarks.restore_user(target, %{"sites" => []}) ==
               {:error, {:unsupported_version, nil}}
    end
  end
end
