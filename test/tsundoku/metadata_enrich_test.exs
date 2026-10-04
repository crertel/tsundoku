defmodule Tsundoku.MetadataEnrichTest do
  use Tsundoku.DataCase, async: true
  use Oban.Testing, repo: Tsundoku.Repo

  import Ecto.Query
  import Tsundoku.AccountsFixtures

  alias Tsundoku.Bookmarks
  alias Tsundoku.Bookmarks.Site
  alias Tsundoku.Metadata
  alias Tsundoku.MetadataServer
  alias Tsundoku.Workers.EnrichMetadata

  setup_all do
    %{base: MetadataServer.start()}
  end

  setup do
    %{user: user_fixture()}
  end

  # Site URL validation rejects localhost, so save a public-looking URL
  # and then point the row at the test server. Each site gets its own
  # domain so DomainMutex locks can't collide with other async tests.
  defp site_fixture(user, url, attrs \\ %{}) do
    {:ok, site} =
      %{
        "url" => "https://example.com/#{System.unique_integer([:positive])}",
        "created_by_id" => user.id,
        "tags" => []
      }
      |> Map.merge(attrs)
      |> Bookmarks.create_site()

    domain = "enrich-#{System.unique_integer([:positive])}.test"
    Repo.update_all(from(s in Site, where: s.id == ^site.id), set: [url: url, domain: domain])
    Repo.get!(Site, site.id)
  end

  # A port nothing is listening on: bind one, note it, and close it.
  defp closed_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  describe "fetch_html/1" do
    test "returns the body of an html page", %{base: base} do
      assert {:ok, html} = Metadata.fetch_html(base <> "/page")
      assert html =~ "Real Title"
    end

    test "follows redirects", %{base: base} do
      assert {:ok, html} = Metadata.fetch_html(base <> "/redirect")
      assert html =~ "Real Title"
    end

    test "reports non-2xx statuses", %{base: base} do
      assert Metadata.fetch_html(base <> "/nope") == {:error, {:http_status, 404}}
      assert Metadata.fetch_html(base <> "/forbidden") == {:error, {:http_status, 403}}
    end

    test "rejects non-html content", %{base: base} do
      assert Metadata.fetch_html(base <> "/image") == {:error, :not_html_or_too_large}
    end

    test "rejects oversized pages", %{base: base} do
      assert Metadata.fetch_html(base <> "/huge") == {:error, :not_html_or_too_large}
    end
  end

  describe "enrich/1" do
    test "stores the page's metadata and favicon", %{base: base, user: user} do
      site = site_fixture(user, base <> "/page")

      assert {:ok, enriched} = Metadata.enrich(site)

      assert enriched.display_name == "Real Title"
      assert enriched.description == "Real description"
      assert enriched.og_image_url == base <> "/cover.jpg"
      assert enriched.favicon_url == base <> "/icon.png"
      assert enriched.favicon_data == MetadataServer.png()
      assert enriched.favicon_content_type == "image/png"
      assert enriched.crawl_status == "ok"
      assert %DateTime{} = enriched.crawled_at
    end

    test "keeps a title the user already set", %{base: base, user: user} do
      site = site_fixture(user, base <> "/page", %{"display_name" => "My Name"})

      assert {:ok, enriched} = Metadata.enrich(site)
      assert enriched.display_name == "My Name"
      assert enriched.description == "Real description"
    end

    test "keeps the site's tags", %{base: base, user: user} do
      {:ok, tag} = Bookmarks.create_tag(%{"name" => "keep", "created_by_id" => user.id})
      site = site_fixture(user, base <> "/page", %{"tags" => [tag]})

      assert {:ok, _} = Metadata.enrich(site)

      assert [%{name: "keep"}] = Repo.get!(Site, site.id) |> Repo.preload(:tags) |> Map.get(:tags)
    end

    test "leaves the favicon empty when it can't be fetched", %{base: base, user: user} do
      site = site_fixture(user, base <> "/bare")

      assert {:ok, enriched} = Metadata.enrich(site)

      assert enriched.display_name == "Bare"
      assert enriched.favicon_url == base <> "/favicon.ico"
      assert enriched.favicon_data == nil
      assert enriched.favicon_content_type == nil
      assert enriched.crawl_status == "ok"
    end

    test "drops oversized favicons", %{base: base, user: user} do
      site = site_fixture(user, base <> "/big-icon-page")

      assert {:ok, enriched} = Metadata.enrich(site)

      assert enriched.favicon_url == base <> "/big.ico"
      assert enriched.favicon_data == nil
      assert enriched.crawl_status == "ok"
    end

    test "records the http status when the page is gone", %{base: base, user: user} do
      site = site_fixture(user, base <> "/nope", %{"display_name" => "Gone"})

      assert {:ok, enriched} = Metadata.enrich(site)

      assert enriched.crawl_status == "http_404"
      assert %DateTime{} = enriched.crawled_at
      assert enriched.display_name == "Gone"
      assert enriched.description == nil
    end

    test "records not_html for non-html content", %{base: base, user: user} do
      site = site_fixture(user, base <> "/image")

      assert {:ok, enriched} = Metadata.enrich(site)
      assert enriched.crawl_status == "not_html"
    end

    test "records server errors by status", %{base: base, user: user} do
      site = site_fixture(user, base <> "/broken")

      assert {:ok, enriched} = Metadata.enrich(site)
      assert enriched.crawl_status == "http_500"
    end

    test "records a timeout when the page doesn't answer in time", %{base: base, user: user} do
      site = site_fixture(user, base <> "/slow", %{"display_name" => "Slow"})

      assert {:ok, enriched} = Metadata.enrich(site)

      assert enriched.crawl_status == "timeout"
      assert %DateTime{} = enriched.crawled_at
      assert enriched.display_name == "Slow"
    end

    test "records a network error when nothing is listening", %{user: user} do
      site = site_fixture(user, "http://localhost:#{closed_port()}/")

      assert {:ok, enriched} = Metadata.enrich(site)
      assert enriched.crawl_status == "network_error"
    end

    test "assumes an .ico when the favicon has no content type", %{base: base, user: user} do
      site = site_fixture(user, base <> "/untyped-icon-page")

      assert {:ok, enriched} = Metadata.enrich(site)

      assert enriched.favicon_data == MetadataServer.png()
      assert enriched.favicon_content_type == "image/x-icon"
    end
  end

  describe "enrich_async/1" do
    test "enqueues a metadata job for the site", %{user: user} do
      {:ok, site} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/queued",
          "created_by_id" => user.id,
          "tags" => []
        })

      assert_enqueued(worker: EnrichMetadata, args: %{site_id: site.id}, queue: :metadata)
    end

    test "does nothing for a blank url" do
      assert Metadata.enrich_async(%Site{id: Ecto.UUID.generate(), url: ""}) == :ok
      assert Metadata.enrich_async(%Site{id: Ecto.UUID.generate(), url: nil}) == :ok

      refute_enqueued(worker: EnrichMetadata)
    end
  end

  describe "EnrichMetadata worker" do
    test "enriches the site and releases the domain lock", %{base: base, user: user} do
      site = site_fixture(user, base <> "/page")

      assert :ok = perform_job(EnrichMetadata, %{site_id: site.id})

      assert Repo.get!(Site, site.id).crawl_status == "ok"
      assert Tsundoku.DomainMutex.try_acquire(site.domain) == :ok
      Tsundoku.DomainMutex.release(site.domain)
    end

    test "snoozes while another fetch holds the domain", %{base: base, user: user} do
      site = site_fixture(user, base <> "/page")

      :ok = Tsundoku.DomainMutex.try_acquire(site.domain)
      on_exit(fn -> Tsundoku.DomainMutex.release(site.domain) end)

      assert {:snooze, 5} = perform_job(EnrichMetadata, %{site_id: site.id})
      assert Repo.get!(Site, site.id).crawl_status == nil
    end

    test "is a no-op when the site has been deleted" do
      assert :ok = perform_job(EnrichMetadata, %{site_id: Ecto.UUID.generate()})
    end
  end
end
