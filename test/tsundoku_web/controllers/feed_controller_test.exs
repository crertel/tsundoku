defmodule TsundokuWeb.FeedControllerTest do
  use TsundokuWeb.ConnCase, async: true

  import Tsundoku.AccountsFixtures
  alias Tsundoku.Bookmarks

  setup do
    user = user_fixture()

    {:ok, search} =
      Bookmarks.create_saved_search(%{name: "Everything", query: "", created_by_id: user.id})

    {:ok, search} = Bookmarks.enable_feed(search)

    %{user: user, search: search}
  end

  defp site_fixture(user, attrs) do
    {:ok, site} =
      %{display_name: "A site", url: "https://example.com", created_by_id: user.id, tags: []}
      |> Map.merge(attrs)
      |> Bookmarks.create_site()

    site
  end

  defp feed(conn, token), do: get(conn, Routes.feed_path(conn, :show, token))

  test "serves the saved search as an Atom feed without logging in", %{
    conn: conn,
    user: user,
    search: search
  } do
    site = site_fixture(user, %{display_name: "First", url: "https://example.com/first"})

    conn = feed(conn, "#{search.feed_token}.atom")

    assert body = response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["application/atom+xml; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=600"]

    assert body =~ ~s(<feed xmlns="http://www.w3.org/2005/Atom">)
    assert body =~ "<title>Everything</title>"
    assert body =~ "<id>urn:uuid:#{search.feed_token}</id>"
    assert body =~ "/feeds/#{search.feed_token}.atom"
    assert body =~ "<id>urn:uuid:#{site.id}</id>"
    assert body =~ "<title>First</title>"
    assert body =~ ~s(<link rel="alternate" href="https://example.com/first" />)
  end

  test "accepts the token without the .atom suffix", %{conn: conn, user: user, search: search} do
    site_fixture(user, %{display_name: "First"})

    assert response(feed(conn, search.feed_token), 200) =~ "<title>First</title>"
  end

  test "renders an empty feed when nothing matches", %{conn: conn, search: search} do
    body = response(feed(conn, "#{search.feed_token}.atom"), 200)

    assert body =~ "<title>Everything</title>"
    refute body =~ "<entry>"
  end

  test "escapes markup in names, titles, and urls", %{conn: conn, user: user} do
    {:ok, search} =
      Bookmarks.create_saved_search(%{name: "Tom & <Jerry>", query: "", created_by_id: user.id})

    {:ok, search} = Bookmarks.enable_feed(search)

    site_fixture(user, %{
      display_name: ~s(<script>"x" & 'y'</script>),
      url: "https://example.com/?a=1&b=2"
    })

    body = response(feed(conn, "#{search.feed_token}.atom"), 200)

    assert body =~ "<title>Tom &amp; &lt;Jerry&gt;</title>"
    assert body =~ "&lt;script&gt;&quot;x&quot; &amp; &apos;y&apos;&lt;/script&gt;"
    assert body =~ ~s(href="https://example.com/?a=1&amp;b=2")
    refute body =~ "<script>"
  end

  test "only includes the owner's sites", %{conn: conn, user: user, search: search} do
    other = user_fixture()
    site_fixture(user, %{display_name: "Mine", url: "https://example.com/mine"})
    site_fixture(other, %{display_name: "Theirs", url: "https://example.com/theirs"})

    body = response(feed(conn, "#{search.feed_token}.atom"), 200)

    assert body =~ "Mine"
    refute body =~ "Theirs"
  end

  test "only includes sites matching the saved query", %{conn: conn, user: user} do
    {:ok, search} =
      Bookmarks.create_saved_search(%{
        name: "Wanted only",
        query: "url:wanted",
        created_by_id: user.id
      })

    {:ok, search} = Bookmarks.enable_feed(search)

    site_fixture(user, %{display_name: "Keep", url: "https://example.com/wanted"})
    site_fixture(user, %{display_name: "Drop", url: "https://example.com/other"})

    body = response(feed(conn, "#{search.feed_token}.atom"), 200)

    assert body =~ "<title>Keep</title>"
    refute body =~ "<title>Drop</title>"
  end

  test "uses notes as the entry summary", %{conn: conn, user: user, search: search} do
    site_fixture(user, %{notes: "worth a second read"})

    body = response(feed(conn, "#{search.feed_token}.atom"), 200)

    assert body =~ ~s(<summary type="text">worth a second read</summary>)
  end

  test "404s for an unknown token", %{conn: conn} do
    assert response(feed(conn, "#{Ecto.UUID.generate()}.atom"), 404) == "Feed not found"
  end

  test "404s for a token that isn't a UUID", %{conn: conn} do
    assert response(feed(conn, "not-a-uuid.atom"), 404) == "Feed not found"
    assert response(feed(conn, "not-a-uuid"), 404) == "Feed not found"
  end

  test "404s once the feed is revoked", %{conn: conn, search: search} do
    old_token = search.feed_token
    {:ok, _} = Bookmarks.disable_feed(search)

    assert response(feed(conn, "#{old_token}.atom"), 404) == "Feed not found"
  end

  test "404s for the old token after rotation", %{conn: conn, search: search} do
    old_token = search.feed_token
    {:ok, rotated} = Bookmarks.enable_feed(search)

    assert rotated.feed_token != old_token
    assert response(feed(conn, "#{old_token}.atom"), 404)
    assert response(feed(conn, "#{rotated.feed_token}.atom"), 200)
  end
end
