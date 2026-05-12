defmodule BookmarkServer.BookmarksTest do
  use BookmarkServer.DataCase

  alias BookmarkServer.Bookmarks
  alias BookmarkServer.AccountsFixtures

  describe "tags" do
    alias BookmarkServer.Bookmarks.Tag

    @valid_attrs %{name: "some name"}
    @update_attrs %{name: "some updated name"}
    @invalid_attrs %{name: nil}

    def tag_fixture(attrs \\ %{}) do
      {:ok, tag} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Bookmarks.create_tag()

      tag
    end

    test "list_tags/0 returns all tags" do
      tag = tag_fixture()
      assert Bookmarks.list_tags() == [tag]
    end

    test "get_tag!/1 returns the tag with given id" do
      tag = tag_fixture()
      assert Bookmarks.get_tag!(tag.id) == tag
    end

    test "create_tag/1 with valid data creates a tag" do
      assert {:ok, %Tag{} = tag} = Bookmarks.create_tag(@valid_attrs)
      assert tag.name == "some name"
    end

    test "create_tag/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Bookmarks.create_tag(@invalid_attrs)
    end

    test "update_tag/2 with valid data updates the tag" do
      tag = tag_fixture()
      assert {:ok, %Tag{} = tag} = Bookmarks.update_tag(tag, @update_attrs)
      assert tag.name == "some updated name"
    end

    test "update_tag/2 with invalid data returns error changeset" do
      tag = tag_fixture()
      assert {:error, %Ecto.Changeset{}} = Bookmarks.update_tag(tag, @invalid_attrs)
      assert tag == Bookmarks.get_tag!(tag.id)
    end

    test "delete_tag/1 deletes the tag" do
      tag = tag_fixture()
      assert {:ok, %Tag{}} = Bookmarks.delete_tag(tag)
      assert_raise Ecto.NoResultsError, fn -> Bookmarks.get_tag!(tag.id) end
    end

    test "change_tag/1 returns a tag changeset" do
      tag = tag_fixture()
      assert %Ecto.Changeset{} = Bookmarks.change_tag(tag)
    end
  end

  describe "sites" do
    alias BookmarkServer.Bookmarks.Site

    @valid_attrs %{display_name: "example dot com", url: "http://www.example.com", tags: []}
    @update_attrs %{display_name: "example dot com 2", url: "http://www.example2.com"}
    @invalid_attrs %{url: nil}

    def site_fixture(attrs \\ %{}) do
      {:ok, site} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Bookmarks.create_site()

      site
    end

    test "list_sites/0 returns all sites" do
      site = site_fixture()
      assert Bookmarks.list_sites() == [site]
    end

    test "get_site!/1 returns the site with given id" do
      site = site_fixture()
      assert Bookmarks.get_site!(site.id) |> BookmarkServer.Repo.preload(:tags) == site
    end

    test "create_site/1 with valid data creates a site" do
      assert {:ok, %Site{} = site} = Bookmarks.create_site(@valid_attrs)
      assert site.url == "http://www.example.com"
    end

    test "create_site/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Bookmarks.create_site(@invalid_attrs)
    end

    test "update_site/2 with valid data updates the site" do
      site = site_fixture()
      assert {:ok, %Site{} = site} = Bookmarks.update_site(site, @update_attrs)
      assert site.url == "http://www.example2.com"
    end

    @tag :uut
    test "update_site/2 with invalid data returns error changeset" do
      site = site_fixture()
      assert {:error, %Ecto.Changeset{}} = Bookmarks.update_site(site, @invalid_attrs)
      assert site == Bookmarks.get_site!(site.id) |> BookmarkServer.Repo.preload(:tags)
    end

    test "delete_site/1 deletes the site" do
      site = site_fixture()
      assert {:ok, %Site{}} = Bookmarks.delete_site(site)
      assert_raise Ecto.NoResultsError, fn -> Bookmarks.get_site!(site.id) end
    end

    test "change_site/1 returns a site changeset" do
      site = site_fixture()
      assert %Ecto.Changeset{} = Bookmarks.change_site(site)
    end

    test "search_and_paginate_sites/2 filters by search text and all selected tags" do
      user = AccountsFixtures.user_fixture()
      {:ok, physics} = Bookmarks.create_tag(%{name: "physics", created_by_id: user.id})
      {:ok, reading} = Bookmarks.create_tag(%{name: "reading", created_by_id: user.id})
      {:ok, cooking} = Bookmarks.create_tag(%{name: "cooking", created_by_id: user.id})

      {:ok, matching_site} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/physics-reading",
          "display_name" => "Physics reading list",
          "created_by_id" => user.id,
          "tags" => [physics, reading]
        })

      {:ok, _missing_tag_site} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/physics",
          "display_name" => "Physics notes",
          "created_by_id" => user.id,
          "tags" => [physics]
        })

      {:ok, _wrong_search_site} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/cooking",
          "display_name" => "Cooking list",
          "created_by_id" => user.id,
          "tags" => [physics, reading, cooking]
        })

      page =
        Bookmarks.search_and_paginate_sites(
          %{
            search_string: "Physics",
            filtering_tags: ["physics", "reading"],
            created_by: user.id
          },
          page: 1,
          page_size: 50
        )

      assert [%Site{id: id}] = page.entries
      assert id == matching_site.id
      assert page.total_entries == 1
    end

    test "search_and_paginate_sites/2 supports fielded tag domain and url terms" do
      user = AccountsFixtures.user_fixture()
      {:ok, elixir} = Bookmarks.create_tag(%{name: "elixir", created_by_id: user.id})
      {:ok, docs} = Bookmarks.create_tag(%{name: "docs", created_by_id: user.id})

      {:ok, matching_site} =
        Bookmarks.create_site(%{
          "url" => "https://docs.example.com/packages/ecto",
          "display_name" => "Ecto docs",
          "created_by_id" => user.id,
          "tags" => [elixir, docs]
        })

      {:ok, _wrong_domain_site} =
        Bookmarks.create_site(%{
          "url" => "https://example.org/packages/ecto",
          "display_name" => "Ecto docs mirror",
          "created_by_id" => user.id,
          "tags" => [elixir, docs]
        })

      {:ok, _wrong_tag_site} =
        Bookmarks.create_site(%{
          "url" => "https://docs.example.com/packages/phoenix",
          "display_name" => "Phoenix docs",
          "created_by_id" => user.id,
          "tags" => [docs]
        })

      page =
        Bookmarks.search_and_paginate_sites(
          %{query: ~s(Ecto tag:elixir domain:example.com url:packages), created_by: user.id},
          page: 1,
          page_size: 50
        )

      assert [%Site{id: id}] = page.entries
      assert id == matching_site.id
      assert page.total_entries == 1
    end

    test "parse_site_query/1 supports quoted field values and aliases" do
      assert %{
               text: ["notes"],
               tags: ["machine learning"],
               domains: ["example.com"],
               urls: ["paper"],
               exclude_tags: ["draft"]
             } =
               Bookmarks.parse_site_query(
                 ~s(notes tag:"machine learning" site:www.example.com url:paper -tag:draft)
               )
    end

    test "parse_site_query/1 handles quoted tag values without spaces" do
      assert %{tags: ["business"]} = Bookmarks.parse_site_query(~s(tag:"business"))
      assert %{tags: ["physics engine"]} = Bookmarks.parse_site_query(~s(tag:"Physics Engine"))
    end

    test "list_domains/1 groups sites by normalized domain with tag counts" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      {:ok, elixir} = Bookmarks.create_tag(%{name: "elixir", created_by_id: user.id})
      {:ok, docs} = Bookmarks.create_tag(%{name: "docs", created_by_id: user.id})

      {:ok, _first_site} =
        Bookmarks.create_site(%{
          "url" => "https://www.example.com/articles",
          "display_name" => "Example articles",
          "created_by_id" => user.id,
          "tags" => [elixir, docs]
        })

      {:ok, _second_site} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/reference",
          "display_name" => "Example reference",
          "created_by_id" => user.id,
          "tags" => [docs]
        })

      {:ok, _other_site} =
        Bookmarks.create_site(%{
          "url" => "https://example.org/reference",
          "display_name" => "Other user's reference",
          "created_by_id" => other_user.id,
          "tags" => []
        })

      assert [
               %{
                 domain: "example.com",
                 count: 2,
                 tags: [%{name: "docs", count: 2}, %{name: "elixir", count: 1}]
               }
             ] = Bookmarks.list_domains(user.id)
    end
  end
end
