defmodule Tsundoku.MetadataServer do
  @moduledoc """
  A real HTTP server for exercising `Tsundoku.Metadata` end to end, so
  crawler tests go through Req rather than a stub.

      setup_all do
        %{base: Tsundoku.MetadataServer.start()}
      end
  """

  use Plug.Router

  plug :match
  plug :dispatch

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>

  @doc "Starts the server on a free port and returns its base URL."
  def start do
    ref = make_ref()
    {:ok, _} = Plug.Cowboy.http(__MODULE__, [], port: 0, ref: ref)
    ExUnit.Callbacks.on_exit(fn -> Plug.Cowboy.shutdown(ref) end)

    "http://localhost:#{:ranch.get_port(ref)}"
  end

  def png, do: @png

  get "/page" do
    html(conn, """
    <html>
      <head>
        <title>Fallback</title>
        <meta property="og:title" content="Real Title" />
        <meta property="og:description" content="Real description" />
        <meta property="og:image" content="/cover.jpg" />
        <link rel="icon" href="/icon.png" />
      </head>
    </html>
    """)
  end

  # No <link rel=icon>, so the crawler falls back to /favicon.ico, which
  # this server doesn't have.
  get "/bare" do
    html(conn, "<html><head><title>Bare</title></head></html>")
  end

  get "/big-icon-page" do
    html(conn, ~s(<html><head><link rel="icon" href="/big.ico" /></head></html>))
  end

  get "/huge" do
    html(conn, String.duplicate("a", 4 * 1_048_576 + 1))
  end

  get "/redirect" do
    conn |> put_resp_header("location", "/page") |> send_resp(302, "")
  end

  get "/icon.png" do
    conn |> put_resp_content_type("image/png") |> send_resp(200, @png)
  end

  get "/big.ico" do
    conn
    |> put_resp_content_type("image/x-icon")
    |> send_resp(200, String.duplicate("a", 512 * 1024 + 1))
  end

  get "/image" do
    conn |> put_resp_content_type("image/png") |> send_resp(200, @png)
  end

  get "/forbidden" do
    send_resp(conn, 403, "nope")
  end

  get "/broken" do
    send_resp(conn, 500, "boom")
  end

  # Outlasts the test env's receive timeout.
  get "/slow" do
    Process.sleep(1_500)
    html(conn, "<html><head><title>Slow</title></head></html>")
  end

  get "/untyped-icon-page" do
    html(conn, ~s(<html><head><link rel="icon" href="/untyped.ico" /></head></html>))
  end

  # A favicon served without a content-type header.
  get "/untyped.ico" do
    send_resp(conn, 200, @png)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp html(conn, body) do
    conn |> put_resp_content_type("text/html") |> send_resp(200, body)
  end
end
