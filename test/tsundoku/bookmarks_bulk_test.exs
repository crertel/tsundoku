defmodule Tsundoku.BookmarksBulkTest do
  use Tsundoku.DataCase, async: true
  use Oban.Testing, repo: Tsundoku.Repo

  alias Tsundoku.AccountsFixtures
  alias Tsundoku.Bookmarks
  alias Tsundoku.Bookmarks.Site
  alias Tsundoku.Workers.EnrichMetadata

  defp site_fixture(user, attrs) do
    {:ok, site} =
      %{
        "created_by_id" => user.id,
        "url" => "https://example.com/#{System.unique_integer([:positive])}",
        "tags" => []
      }
      |> Map.merge(attrs)
      |> Bookmarks.create_site()

    site
  end

  defp tag_fixture(user, name) do
    {:ok, tag} = Bookmarks.create_tag(%{"name" => name, "created_by_id" => user.id})
    tag
  end

  defp mark_crawled(site) do
    Repo.update_all(from(s in Site, where: s.id == ^site.id),
      set: [crawled_at: DateTime.utc_now()]
    )
  end

  describe "delete_sites_for_tag/1" do
    test "deletes the tagged sites, keeps the tag, and broadcasts once" do
      user = AccountsFixtures.user_fixture()
      doomed = tag_fixture(user, "doomed")
      other_tag = tag_fixture(user, "other")

      site_fixture(user, %{"tags" => [doomed]})
      site_fixture(user, %{"tags" => [doomed, other_tag]})
      kept = site_fixture(user, %{"tags" => [other_tag]})
      untagged = site_fixture(user, %{})

      Bookmarks.subscribe(user.id)

      assert Bookmarks.delete_sites_for_tag(doomed) == {2, nil}

      assert_receive {:bookmarks_event, :bulk_changed, %{sites_deleted: 2}}
      refute_receive {:bookmarks_event, _, _}, 50

      assert Bookmarks.get_tag(doomed.id)
      assert Bookmarks.count_sites_for_tag(doomed) == 0
      assert Bookmarks.get_site(kept.id)
      assert Bookmarks.get_site(untagged.id)
      assert Bookmarks.count_user_sites(user.id) == 2
    end

    test "does nothing and stays quiet when the tag has no sites" do
      user = AccountsFixtures.user_fixture()
      empty = tag_fixture(user, "empty")
      site_fixture(user, %{})

      Bookmarks.subscribe(user.id)

      assert Bookmarks.delete_sites_for_tag(empty) == {0, nil}

      refute_receive {:bookmarks_event, _, _}, 50
      assert Bookmarks.count_user_sites(user.id) == 1
    end
  end

  describe "empty_user_data/1" do
    test "deletes the user's sites and tags and leaves other users alone" do
      user = AccountsFixtures.user_fixture()
      other = AccountsFixtures.user_fixture()

      tag = tag_fixture(user, "mine")
      site_fixture(user, %{"tags" => [tag]})
      site_fixture(user, %{})

      their_tag = tag_fixture(other, "theirs")
      site_fixture(other, %{"tags" => [their_tag]})

      Bookmarks.subscribe(user.id)

      assert Bookmarks.empty_user_data(user) == {:ok, %{sites_deleted: 2, tags_deleted: 1}}

      assert_receive {:bookmarks_event, :bulk_changed, %{sites_deleted: 2, tags_deleted: 1}}

      assert Bookmarks.count_user_sites(user.id) == 0
      assert Bookmarks.list_user_tags(user.id) == []
      assert Bookmarks.count_user_sites(other.id) == 1
      assert Bookmarks.count_sites_for_tag(their_tag) == 1
    end

    test "succeeds on an already-empty account" do
      user = AccountsFixtures.user_fixture()

      assert Bookmarks.empty_user_data(user) == {:ok, %{sites_deleted: 0, tags_deleted: 0}}
    end
  end

  describe "enqueue_metadata_backfill/1" do
    setup do
      user = AccountsFixtures.user_fixture()
      other = AccountsFixtures.user_fixture()

      crawled = site_fixture(user, %{})
      mark_crawled(crawled)
      pending = site_fixture(user, %{})
      theirs = site_fixture(other, %{})

      # create_site/1 enqueues a job per site; start from a clean queue.
      Repo.delete_all(Oban.Job)

      %{user: user, crawled: crawled, pending: pending, theirs: theirs}
    end

    defp enqueued_site_ids do
      [worker: EnrichMetadata] |> all_enqueued() |> Enum.map(& &1.args["site_id"]) |> Enum.sort()
    end

    test "enqueues only uncrawled sites by default", %{pending: pending, theirs: theirs} do
      assert Bookmarks.enqueue_metadata_backfill() == 2
      assert enqueued_site_ids() == Enum.sort([pending.id, theirs.id])
    end

    test "force: true re-enqueues crawled sites too", ctx do
      assert Bookmarks.enqueue_metadata_backfill(force: true) == 3
      assert enqueued_site_ids() == Enum.sort([ctx.crawled.id, ctx.pending.id, ctx.theirs.id])
    end

    test "user_id: scopes the backfill to one user", %{user: user, pending: pending} do
      assert Bookmarks.enqueue_metadata_backfill(user_id: user.id) == 1
      assert enqueued_site_ids() == [pending.id]
    end

    test "combines force and user_id", %{user: user, crawled: crawled, pending: pending} do
      assert Bookmarks.enqueue_metadata_backfill(user_id: user.id, force: true) == 2
      assert enqueued_site_ids() == Enum.sort([crawled.id, pending.id])
    end
  end

  describe "saved searches" do
    setup do
      %{user: AccountsFixtures.user_fixture()}
    end

    defp saved_search_fixture(user, attrs \\ %{}) do
      {:ok, search} =
        %{name: "A search", query: "tag:elixir", created_by_id: user.id}
        |> Map.merge(attrs)
        |> Bookmarks.create_saved_search()

      search
    end

    test "create_saved_search/1 stores the query without a feed token", %{user: user} do
      search = saved_search_fixture(user)

      assert search.name == "A search"
      assert search.query == "tag:elixir"
      assert search.feed_token == nil
      assert Bookmarks.get_saved_search!(search.id).id == search.id
    end

    test "create_saved_search/1 requires a name of at most 100 characters", %{user: user} do
      assert {:error, changeset} = Bookmarks.create_saved_search(%{created_by_id: user.id})
      assert %{name: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} =
               Bookmarks.create_saved_search(%{
                 name: String.duplicate("x", 101),
                 created_by_id: user.id
               })

      assert %{name: [_]} = errors_on(changeset)
    end

    test "names are unique per user, not globally", %{user: user} do
      saved_search_fixture(user, %{name: "Dupe"})

      assert {:error, changeset} =
               Bookmarks.create_saved_search(%{name: "Dupe", created_by_id: user.id})

      refute changeset.valid?

      other = AccountsFixtures.user_fixture()
      assert {:ok, _} = Bookmarks.create_saved_search(%{name: "Dupe", created_by_id: other.id})
    end

    test "list_user_saved_searches/1 is alphabetical and scoped to the user", %{user: user} do
      saved_search_fixture(user, %{name: "Zebra"})
      saved_search_fixture(user, %{name: "Apple"})
      saved_search_fixture(AccountsFixtures.user_fixture(), %{name: "Theirs"})

      assert Enum.map(Bookmarks.list_user_saved_searches(user.id), & &1.name) == [
               "Apple",
               "Zebra"
             ]
    end

    test "update_saved_search/2 and change_saved_search/2", %{user: user} do
      search = saved_search_fixture(user)

      assert {:ok, updated} =
               Bookmarks.update_saved_search(search, %{name: "Renamed", query: "tag:rust"})

      assert updated.name == "Renamed"
      assert updated.query == "tag:rust"

      assert {:error, _} = Bookmarks.update_saved_search(search, %{name: ""})
      assert %Ecto.Changeset{valid?: true} = Bookmarks.change_saved_search(search)
      refute Bookmarks.change_saved_search(search, %{name: ""}).valid?
    end

    test "delete_saved_search/1", %{user: user} do
      search = saved_search_fixture(user)

      assert {:ok, _} = Bookmarks.delete_saved_search(search)
      assert Bookmarks.list_user_saved_searches(user.id) == []
    end

    test "enable_feed/1 issues a token, rotates it, and disable_feed/1 revokes it", %{user: user} do
      search = saved_search_fixture(user)

      assert {:ok, enabled} = Bookmarks.enable_feed(search)
      assert {:ok, _} = Ecto.UUID.cast(enabled.feed_token)
      assert Bookmarks.get_saved_search_by_token(enabled.feed_token).id == search.id

      assert {:ok, rotated} = Bookmarks.enable_feed(enabled)
      assert rotated.feed_token != enabled.feed_token
      assert Bookmarks.get_saved_search_by_token(enabled.feed_token) == nil

      assert {:ok, disabled} = Bookmarks.disable_feed(rotated)
      assert disabled.feed_token == nil
      assert Bookmarks.get_saved_search_by_token(rotated.feed_token) == nil
    end

    test "search_results_for_feed/2 runs the saved query, capped at the limit", %{user: user} do
      elixir = tag_fixture(user, "elixir")
      for _ <- 1..3, do: site_fixture(user, %{"tags" => [elixir]})
      site_fixture(user, %{})

      search = saved_search_fixture(user)

      assert length(Bookmarks.search_results_for_feed(search)) == 3
      assert length(Bookmarks.search_results_for_feed(search, limit: 2)) == 2
    end
  end
end
