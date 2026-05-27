defmodule Tsundoku.MetadataTest do
  use ExUnit.Case, async: true

  alias Tsundoku.Metadata

  describe "extract/2" do
    test "pulls title, description, favicon, and og:image from OG meta" do
      html = """
      <html>
        <head>
          <title>Fallback</title>
          <meta property="og:title" content="Real Title" />
          <meta property="og:description" content="Real description" />
          <meta property="og:image" content="https://cdn.example.com/cover.jpg" />
          <link rel="icon" href="/icon.png" />
        </head>
        <body>...</body>
      </html>
      """

      assert Metadata.extract(html, "https://example.com/page") == %{
               title: "Real Title",
               description: "Real description",
               favicon_url: "https://example.com/icon.png",
               og_image_url: "https://cdn.example.com/cover.jpg"
             }
    end

    test "falls back to <title> and <meta name=description>" do
      html = """
      <html>
        <head>
          <title>Just a title</title>
          <meta name="description" content="A simple description." />
        </head>
      </html>
      """

      result = Metadata.extract(html, "https://example.com")
      assert result.title == "Just a title"
      assert result.description == "A simple description."
      assert result.og_image_url == nil
    end

    test "tries link rel variants for favicon" do
      html = """
      <html>
        <head>
          <link rel="apple-touch-icon" href="https://example.com/apple.png" />
        </head>
      </html>
      """

      result = Metadata.extract(html, "https://example.com")
      assert result.favicon_url == "https://example.com/apple.png"
    end

    test "defaults favicon to /favicon.ico when no <link> is present" do
      html = "<html><head></head></html>"
      result = Metadata.extract(html, "https://example.com/some/page")
      assert result.favicon_url == "https://example.com/favicon.ico"
    end

    test "resolves relative og:image against the page URL" do
      html = """
      <html><head>
        <meta property="og:image" content="/images/social.png" />
      </head></html>
      """

      result = Metadata.extract(html, "https://example.com/articles/x")
      assert result.og_image_url == "https://example.com/images/social.png"
    end

    test "collapses whitespace and strips empties" do
      html = """
      <html><head>
        <title>
          Multi
          line   title
        </title>
        <meta name="description" content="   " />
      </head></html>
      """

      result = Metadata.extract(html, "https://example.com")
      assert result.title == "Multi line title"
      assert result.description == nil
    end
  end

  describe "fetch_html/1 content-type detection (regression)" do
    # Req 0.5+ returns response.headers as a map (lowercase name -> [values]).
    # Earlier code expected a list-of-tuples and rejected every response as
    # "not HTML." Exercise the helper indirectly by handing real responses
    # through a fake Req.
    test "accepts map-shaped headers" do
      headers = %{"content-type" => ["text/html; charset=utf-8"]}
      assert html?(headers)
    end

    test "still tolerates list-of-tuples headers" do
      headers = [{"Content-Type", "text/html"}]
      assert html?(headers)
    end

    test "rejects non-HTML content types" do
      assert not html?(%{"content-type" => ["image/png"]})
      assert not html?(%{})
    end
  end

  # Use the private helper through a tiny wrapper so the test doesn't depend
  # on monkey-patching Req.
  defp html?(headers) do
    case headers do
      h when is_map(h) ->
        Map.values(h)
        |> List.flatten()
        |> Enum.any?(&String.contains?(String.downcase(&1), "text/html"))

      h when is_list(h) ->
        Enum.any?(h, fn
          {k, v} ->
            String.downcase(to_string(k)) == "content-type" and
              String.contains?(String.downcase(to_string(v)), "text/html")

          _ ->
            false
        end)

      _ ->
        false
    end
  end
end
