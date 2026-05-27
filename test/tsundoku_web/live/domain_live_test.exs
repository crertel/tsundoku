defmodule TsundokuWeb.DomainLiveTest do
  use TsundokuWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Tsundoku.Bookmarks

  describe "Index" do
    test "lists bookmark domains with tag counts", %{conn: conn} do
      user = Tsundoku.AccountsFixtures.user_fixture(confirmed: true)
      {:ok, tag} = Bookmarks.create_tag(%{name: "elixir", created_by_id: user.id})

      {:ok, _site} =
        Bookmarks.create_site(%{
          "url" => "https://www.example.com/articles",
          "display_name" => "Example articles",
          "created_by_id" => user.id,
          "tags" => [tag]
        })

      conn = log_in_user(conn, user)
      {:ok, _index_live, html} = live(conn, Routes.domain_index_path(conn, :index))

      assert html =~ "Domains"
      assert html =~ "example.com"
      assert html =~ "1 bookmark"
      assert html =~ "elixir"
    end
  end
end
