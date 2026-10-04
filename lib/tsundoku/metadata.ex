defmodule Tsundoku.Metadata do
  @moduledoc """
  Fetches a page over HTTP and extracts user-facing metadata (title,
  description, favicon, og:image). Designed to be called as fire-and-forget
  background work via `enrich_async/1`; failures are logged and silently
  drop the metadata for that site.
  """

  require Logger

  alias Tsundoku.Bookmarks.Site
  alias Tsundoku.Repo

  # Imitate a stock Firefox so bot-blockers like Cloudflare default rules
  # don't reject the request outright. Also send the browser-y Accept and
  # Accept-Language so the request looks like one a real client would
  # make.
  @user_agent "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
  @accept "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
  @accept_language "en-US,en;q=0.5"
  @receive_timeout 10_000
  # Don't read more than ~4 MB of HTML.
  @max_body_size 4 * 1_048_576

  @typedoc "Result of parsing a page; any field may be nil."
  @type extracted :: %{
          title: String.t() | nil,
          description: String.t() | nil,
          favicon_url: String.t() | nil,
          og_image_url: String.t() | nil
        }

  @doc """
  Schedules a background task to fetch metadata for the site and update
  the corresponding row. Returns immediately. Does nothing if the URL is
  blank.
  """
  def enrich_async(%Site{} = site) do
    if is_binary(site.url) and site.url != "" do
      %{site_id: site.id}
      |> Tsundoku.Workers.EnrichMetadata.new()
      |> Oban.insert()
    end

    :ok
  end

  @doc """
  Synchronous: fetch the page, parse metadata, update the site. Returns
  `{:ok, site}` or `{:error, reason}`. Intended for tests and scripts;
  production paths should use `enrich_async/1`.
  """
  def enrich(%Site{} = site) do
    now = DateTime.utc_now()
    site_with_tags = Repo.preload(site, :tags)

    attrs =
      case fetch_html(site.url) do
        {:ok, html} ->
          extracted = extract(html, site.url)
          {favicon_data, favicon_ct} = fetch_favicon(extracted.favicon_url)

          %{
            "description" => extracted.description,
            "favicon_url" => extracted.favicon_url,
            "favicon_data" => favicon_data,
            "favicon_content_type" => favicon_ct,
            "og_image_url" => extracted.og_image_url,
            "crawled_at" => now,
            "crawl_status" => "ok"
          }
          |> maybe_fill_title(site, extracted.title)

        {:error, reason} ->
          Logger.info("metadata fetch failed for #{site.url}: #{inspect(reason)}")

          %{
            "crawled_at" => now,
            "crawl_status" => status_from_reason(reason)
          }
      end
      |> Map.put("tags", site_with_tags.tags || [])

    site_with_tags
    |> Site.changeset(attrs)
    |> Repo.update()
  end

  defp status_from_reason({:http_status, code}), do: "http_#{code}"
  defp status_from_reason(:timeout), do: "timeout"
  defp status_from_reason(:not_html_or_too_large), do: "not_html"
  defp status_from_reason(:invalid_url), do: "invalid_url"

  defp status_from_reason(%{reason: :timeout}), do: "timeout"
  defp status_from_reason(%{__struct__: mod}) when is_atom(mod), do: "network_error"
  defp status_from_reason(_), do: "error"

  # Favicons over 512 KB are almost certainly mislabeled. Failures are
  # silent: a missing favicon doesn't fail the rest of the enrichment.
  @favicon_max_body_size 512 * 1024

  defp fetch_favicon(nil), do: {nil, nil}
  defp fetch_favicon(""), do: {nil, nil}

  defp fetch_favicon(url) do
    case get(url, [{"user-agent", @user_agent}]) do
      {:ok, %Req.Response{status: status, body: body, headers: headers}}
      when status in 200..299 ->
        if byte_size(body) <= @favicon_max_body_size do
          {body, favicon_content_type(headers)}
        else
          {nil, nil}
        end

      _ ->
        {nil, nil}
    end
  rescue
    _ -> {nil, nil}
  end

  defp favicon_content_type(headers) do
    headers
    |> content_type_values()
    |> List.first()
    |> case do
      nil -> "image/x-icon"
      ct -> ct |> String.split(";") |> List.first() |> String.trim()
    end
  end

  @doc "Returns `{:ok, html}` on success, `{:error, reason}` otherwise."
  def fetch_html(url) do
    case get(url, [
           {"user-agent", @user_agent},
           {"accept", @accept},
           {"accept-language", @accept_language}
         ]) do
      {:ok, %Req.Response{status: status, body: body, headers: headers}}
      when status in 200..299 ->
        if html?(headers) and byte_size(body) <= @max_body_size do
          {:ok, to_utf8(body)}
        else
          {:error, :not_html_or_too_large}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # `:metadata_req_options` overrides the defaults; the test env uses it
  # to turn off Req's retry backoff and shorten the timeout.
  defp get(url, headers) do
    [headers: headers, receive_timeout: @receive_timeout, max_redirects: 5, decode_body: false]
    |> Keyword.merge(Application.get_env(:tsundoku, :metadata_req_options, []))
    |> then(&Req.get(url, &1))
  rescue
    # Req raises on URLs it can't request at all: no host, or a scheme
    # other than http(s).
    ArgumentError -> {:error, :invalid_url}
  end

  # Postgres rejects text that isn't valid UTF-8, which would fail the
  # whole update. Bodies that aren't UTF-8 are read as Latin-1, the usual
  # legacy encoding; pages in other legacy encodings come out garbled
  # but still get crawled.
  defp to_utf8(body) do
    if String.valid?(body), do: body, else: :unicode.characters_to_binary(body, :latin1)
  end

  @doc """
  Parses an HTML body and returns the extracted metadata. `page_url` is
  used to resolve relative favicon / og:image URLs.
  """
  def extract(html, page_url) when is_binary(html) and is_binary(page_url) do
    {:ok, doc} = Floki.parse_document(html)

    %{
      title: og_meta(doc, "og:title") || tag_text(doc, "title"),
      description: og_meta(doc, "og:description") || named_meta(doc, "description"),
      favicon_url: favicon_url(doc, page_url),
      og_image_url: og_meta(doc, "og:image") |> absolutize(page_url)
    }
  end

  defp og_meta(doc, property) do
    doc
    |> Floki.find(~s(meta[property="#{property}"]))
    |> Floki.attribute("content")
    |> List.first()
    |> normalize_text()
  end

  defp named_meta(doc, name) do
    doc
    |> Floki.find(~s(meta[name="#{name}"]))
    |> Floki.attribute("content")
    |> List.first()
    |> normalize_text()
  end

  defp tag_text(doc, tag) do
    doc
    |> Floki.find(tag)
    |> Floki.text(sep: " ")
    |> normalize_text()
  end

  defp favicon_url(doc, page_url) do
    rels = ["icon", "shortcut icon", "apple-touch-icon", "apple-touch-icon-precomposed"]

    href =
      Enum.find_value(rels, fn rel ->
        doc
        |> Floki.find(~s(link[rel="#{rel}"]))
        |> Floki.attribute("href")
        |> List.first()
      end)

    cond do
      is_binary(href) and href != "" ->
        absolutize(href, page_url)

      true ->
        absolutize("/favicon.ico", page_url)
    end
  end

  defp absolutize(nil, _base), do: nil
  defp absolutize("", _base), do: nil

  defp absolutize(href, base) do
    case URI.merge(URI.parse(base), URI.parse(href)) do
      %URI{} = uri -> URI.to_string(uri)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp normalize_text(nil), do: nil

  defp normalize_text(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" -> nil
      s -> s
    end
  end

  # Req 0.5+ returns headers as a map of lowercase name → list-of-strings.
  # We tolerate older list-of-tuples shapes too, just in case.
  defp html?(headers) do
    headers
    |> content_type_values()
    |> Enum.any?(&String.contains?(&1, "text/html"))
  end

  defp content_type_values(headers) when is_map(headers) do
    Enum.flat_map(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == "content-type" do
        v |> List.wrap() |> Enum.map(&String.downcase/1)
      else
        []
      end
    end)
  end

  defp content_type_values(headers) when is_list(headers) do
    Enum.flat_map(headers, fn
      {k, v} ->
        if String.downcase(to_string(k)) == "content-type" do
          v |> List.wrap() |> Enum.map(&String.downcase/1)
        else
          []
        end

      _ ->
        []
    end)
  end

  defp content_type_values(_), do: []

  defp maybe_fill_title(attrs, %Site{display_name: existing}, _fetched)
       when is_binary(existing) and existing != "" do
    attrs
  end

  defp maybe_fill_title(attrs, _site, fetched) when is_binary(fetched) do
    Map.put(attrs, "display_name", fetched)
  end

  defp maybe_fill_title(attrs, _site, _fetched), do: attrs
end
