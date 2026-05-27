defmodule BookmarkServerWeb.FeedController do
  use BookmarkServerWeb, :controller

  alias BookmarkServer.Bookmarks
  alias BookmarkServer.Bookmarks.SavedSearch

  @cache_seconds 600

  def show(conn, %{"token" => token}) do
    token = String.trim_trailing(token, ".atom")

    case Bookmarks.get_saved_search_by_token(token) do
      %SavedSearch{} = ss ->
        entries = Bookmarks.search_results_for_feed(ss, limit: 50)
        body = render_atom(conn, ss, entries)

        conn
        |> put_resp_content_type("application/atom+xml")
        |> put_resp_header("cache-control", "public, max-age=#{@cache_seconds}")
        |> send_resp(200, body)

      nil ->
        conn |> send_resp(404, "Feed not found") |> halt()
    end
  end

  defp render_atom(conn, %SavedSearch{} = ss, entries) do
    self_url = Phoenix.VerifiedRoutes.unverified_url(conn, "/feeds/#{ss.feed_token}.atom")
    updated_at = feed_updated_at(entries, ss)

    """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>#{escape(ss.name)}</title>
      <id>urn:uuid:#{ss.feed_token}</id>
      <updated>#{iso(updated_at)}</updated>
      <link rel="self" href="#{escape(self_url)}" />
      <generator>Tsundoku</generator>
    #{Enum.map_join(entries, "\n", &render_entry/1)}
    </feed>
    """
  end

  defp render_entry(site) do
    summary = site.notes || site.description || ""
    title = site.display_name || site.url

    """
      <entry>
        <id>urn:uuid:#{site.id}</id>
        <title>#{escape(title)}</title>
        <link rel="alternate" href="#{escape(site.url)}" />
        <updated>#{iso(site.inserted_at)}</updated>
        <summary type="text">#{escape(summary)}</summary>
      </entry>\
    """
  end

  defp feed_updated_at([], %{updated_at: at}), do: at
  defp feed_updated_at([%{inserted_at: at} | _], _), do: at

  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"
  defp iso(_), do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp escape(nil), do: ""

  defp escape(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
