defmodule Tsundoku.CrawlTest do
  use Tsundoku.DataCase
  use Oban.Testing, repo: Tsundoku.Repo

  alias Tsundoku.AccountsFixtures
  alias Tsundoku.Bookmarks
  alias Tsundoku.Bookmarks.Site
  alias Tsundoku.Crawl
  alias Tsundoku.Crawl.Settings
  alias Tsundoku.Workers.EnrichMetadata

  # Saves a site, clears the crawl job that saving enqueues, and sets
  # its crawl status (nil = never crawled).
  defp site_fixture(user, status \\ nil) do
    {:ok, site} =
      Bookmarks.create_site(%{
        "url" => "https://example.com/#{System.unique_integer([:positive])}",
        "created_by_id" => user.id,
        "tags" => []
      })

    Repo.delete_all(Oban.Job)

    if status do
      Repo.update_all(from(s in Site, where: s.id == ^site.id),
        set: [crawl_status: status, crawled_at: DateTime.utc_now()]
      )
    end

    site
  end

  defp enqueued_site_ids do
    [worker: EnrichMetadata] |> all_enqueued() |> Enum.map(& &1.args["site_id"]) |> Enum.sort()
  end

  describe "settings" do
    test "default to the configured queue limit before any are saved" do
      settings = Crawl.get_settings()

      assert settings.concurrency == 5
      assert settings.delay_ms == 1_000
      assert settings.timeout_ms == 10_000
      assert settings.paused == false
      assert Repo.aggregate(Settings, :count) == 0
    end

    test "update_settings/1 saves and keeps a single row" do
      assert {:ok, saved} = Crawl.update_settings(%{concurrency: 2, delay_ms: 250})
      assert saved.concurrency == 2
      assert saved.delay_ms == 250

      assert {:ok, _} = Crawl.update_settings(%{"timeout_ms" => "3000"})

      assert Repo.aggregate(Settings, :count) == 1
      assert %{concurrency: 2, delay_ms: 250, timeout_ms: 3_000} = Crawl.get_settings()
    end

    test "update_settings/1 rejects out-of-range values" do
      assert {:error, changeset} =
               Crawl.update_settings(%{concurrency: 0, delay_ms: -1, timeout_ms: 500})

      assert %{concurrency: [_], delay_ms: [_], timeout_ms: [_]} = errors_on(changeset)

      assert {:error, changeset} =
               Crawl.update_settings(%{concurrency: 21, delay_ms: 60_001, timeout_ms: 60_001})

      assert %{concurrency: [_], delay_ms: [_], timeout_ms: [_]} = errors_on(changeset)
      assert Repo.aggregate(Settings, :count) == 0
    end

    test "pause/0 and resume/0 persist the flag" do
      assert {:ok, %{paused: true}} = Crawl.pause()
      assert Crawl.get_settings().paused

      assert {:ok, %{paused: false}} = Crawl.resume()
      refute Crawl.get_settings().paused
    end

    test "queue_status/0 is nil when the queue isn't running" do
      assert Crawl.queue_status() == nil
    end

    test "apply_saved_settings/1 does nothing when none are saved" do
      assert Crawl.apply_saved_settings(1) == :ok
    end
  end

  describe "with a running queue" do
    # The app's own Oban instance doesn't run queues in the test env, so
    # point Crawl at one that does. The PG notifier keeps its signals out
    # of the sandboxed database.
    setup do
      start_supervised!(
        {Oban,
         name: Tsundoku.CrawlTest.Oban,
         repo: Repo,
         queues: [metadata: 5],
         notifier: Oban.Notifiers.PG,
         testing: :disabled,
         plugins: false,
         peer: false}
      )

      Application.put_env(:tsundoku, :crawl_oban, Tsundoku.CrawlTest.Oban)
      on_exit(fn -> Application.delete_env(:tsundoku, :crawl_oban) end)

      # Pause straight away so the queue never picks up a job mid-test.
      {:ok, _} = Crawl.pause()
      await_queue(%{paused: true})
      :ok
    end

    defp await_queue(expected, attempts \\ 40) do
      status = Crawl.queue_status()

      cond do
        status && Map.take(status, Map.keys(expected)) == expected ->
          status

        attempts == 0 ->
          flunk("queue never reached #{inspect(expected)}, last: #{inspect(status)}")

        true ->
          Process.sleep(50) && await_queue(expected, attempts - 1)
      end
    end

    test "update_settings/1 scales the queue" do
      assert %{limit: 5, running: 0} = Crawl.queue_status()

      {:ok, _} = Crawl.update_settings(%{concurrency: 2})

      assert %{limit: 2, paused: true} = await_queue(%{limit: 2})
    end

    test "resume/0 and pause/0 control the queue" do
      {:ok, _} = Crawl.resume()
      await_queue(%{paused: false})

      {:ok, _} = Crawl.pause()
      await_queue(%{paused: true})
    end

    test "apply_saved_settings/1 brings a fresh queue in line with what was saved" do
      # Saved while this queue was at its configured defaults...
      Repo.update_all(Settings, set: [concurrency: 3, paused: false])
      assert %{limit: 5, paused: true} = Crawl.queue_status()

      # ...and applied the way boot does.
      assert Crawl.apply_saved_settings() == :ok
      assert %{limit: 3, paused: false} = Crawl.queue_status()
    end
  end

  describe "stats/0" do
    test "counts bookmarks by crawl result, across users" do
      user = AccountsFixtures.user_fixture()
      other = AccountsFixtures.user_fixture()

      site_fixture(user)
      site_fixture(user, "ok")
      site_fixture(other, "ok")
      site_fixture(user, "http_404")
      site_fixture(other, "timeout")
      site_fixture(other, "http_404")

      stats = Crawl.stats()

      assert stats.total == 6
      assert stats.ok == 2
      assert stats.failed == 3
      assert stats.uncrawled == 1
      assert stats.by_status == [{"http_404", 2}, {"ok", 2}, {"timeout", 1}]
      assert length(stats.recent) == 5
      assert stats.jobs == %{}
      assert stats.pending == 0
    end

    test "counts crawl jobs and what's waiting" do
      user = AccountsFixtures.user_fixture()
      site_fixture(user)
      site_fixture(user)

      assert Crawl.enqueue(:uncrawled) == 2

      stats = Crawl.stats()
      assert stats.jobs == %{"available" => 2}
      assert stats.pending == 2
    end

    test "is all zeroes on an empty server" do
      assert %{total: 0, ok: 0, failed: 0, uncrawled: 0, by_status: [], recent: [], pending: 0} =
               Crawl.stats()
    end
  end

  describe "enqueue/1" do
    setup do
      user = AccountsFixtures.user_fixture()

      %{
        uncrawled: site_fixture(user),
        ok: site_fixture(user, "ok"),
        failed: site_fixture(user, "http_500")
      }
    end

    test ":uncrawled queues only never-crawled bookmarks", ctx do
      assert Crawl.enqueue(:uncrawled) == 1
      assert enqueued_site_ids() == [ctx.uncrawled.id]
    end

    test ":failed queues only bookmarks whose last crawl wasn't ok", ctx do
      assert Crawl.enqueue(:failed) == 1
      assert enqueued_site_ids() == [ctx.failed.id]
    end

    test ":all queues everything", ctx do
      assert Crawl.enqueue(:all) == 3
      assert enqueued_site_ids() == Enum.sort([ctx.uncrawled.id, ctx.ok.id, ctx.failed.id])
    end

    test "skips bookmarks that already have a crawl waiting", ctx do
      assert Crawl.enqueue(:uncrawled) == 1
      assert Crawl.enqueue(:uncrawled) == 0
      assert Crawl.enqueue(:all) == 2

      assert enqueued_site_ids() == Enum.sort([ctx.uncrawled.id, ctx.ok.id, ctx.failed.id])
    end

    test "queues again once the earlier job has finished", ctx do
      assert Crawl.enqueue(:uncrawled) == 1
      Repo.update_all(Oban.Job, set: [state: "completed"])

      assert Crawl.enqueue(:uncrawled) == 1
      assert [_] = all_enqueued(worker: EnrichMetadata, args: %{site_id: ctx.uncrawled.id})
    end
  end
end
