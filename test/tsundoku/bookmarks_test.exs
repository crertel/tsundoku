defmodule Tsundoku.BookmarksTest do
  use Tsundoku.DataCase

  alias Tsundoku.Bookmarks
  alias Tsundoku.AccountsFixtures

  describe "tags" do
    alias Tsundoku.Bookmarks.Tag

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

    test "list_global_tags/0 returns all tags" do
      tag = tag_fixture()
      assert Bookmarks.list_global_tags() == [tag]
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

    test "merge_tags/2 moves bookmarks onto the destination and deletes the source" do
      user = AccountsFixtures.user_fixture()
      {:ok, src} = Bookmarks.create_tag(%{name: "old", created_by_id: user.id})
      {:ok, dest} = Bookmarks.create_tag(%{name: "new", created_by_id: user.id})

      {:ok, site_a} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/a",
          "display_name" => "A",
          "created_by_id" => user.id,
          "tags" => [src]
        })

      {:ok, site_b} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/b",
          "display_name" => "B",
          "created_by_id" => user.id,
          "tags" => [src, dest]
        })

      assert {:ok, result} = Bookmarks.merge_tags(src, dest)
      assert result.moved == 2

      assert Bookmarks.get_tag(src.id) == nil

      assert site_a
             |> Tsundoku.Repo.preload(:tags, force: true)
             |> Map.get(:tags)
             |> Enum.map(& &1.id) == [dest.id]

      assert site_b
             |> Tsundoku.Repo.preload(:tags, force: true)
             |> Map.get(:tags)
             |> Enum.map(& &1.id) == [dest.id]
    end

    test "merge_tags/2 refuses to merge a tag into itself" do
      user = AccountsFixtures.user_fixture()
      {:ok, tag} = Bookmarks.create_tag(%{name: "alone", created_by_id: user.id})

      assert {:error, :same_tag} = Bookmarks.merge_tags(tag, tag)
      assert Bookmarks.get_tag(tag.id) != nil
    end
  end

  describe "sites" do
    alias Tsundoku.Bookmarks.Site

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

    test "list_global_sites/0 returns all sites" do
      site = site_fixture()
      assert Bookmarks.list_global_sites() == [site]
    end

    test "get_site!/1 returns the site with given id" do
      site = site_fixture()
      assert Bookmarks.get_site!(site.id) |> Tsundoku.Repo.preload(:tags) == site
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
      assert site == Bookmarks.get_site!(site.id) |> Tsundoku.Repo.preload(:tags)
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
               bare_phrase: "notes",
               titles: [],
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

    test "parse_site_query/1 collapses bare and quoted text into a single phrase" do
      assert %{bare_phrase: "the art of programming", titles: []} =
               Bookmarks.parse_site_query(~s(the art of programming))

      assert %{bare_phrase: "this is a string", titles: []} =
               Bookmarks.parse_site_query(~s("this is a string"))

      assert %{bare_phrase: "the art of modern programming", titles: []} =
               Bookmarks.parse_site_query(~s(the art of "modern programming"))
    end

    test "parse_site_query/1 supports title: field" do
      assert %{bare_phrase: "", titles: ["this is a string"]} =
               Bookmarks.parse_site_query(~s(title:"this is a string"))

      assert %{bare_phrase: "extra", titles: ["foo bar"], tags: ["x"]} =
               Bookmarks.parse_site_query(~s(extra title:"foo bar" tag:x))

      assert %{exclude_titles: ["draft notes"]} =
               Bookmarks.parse_site_query(~s(-title:"draft notes"))
    end

    test "parse_site_query/1 supports metadata:has and metadata:missing" do
      assert %{has_metadata: true} = Bookmarks.parse_site_query("metadata:has")
      assert %{has_metadata: true} = Bookmarks.parse_site_query("metadata:fetched")
      assert %{has_metadata: false} = Bookmarks.parse_site_query("metadata:missing")
      assert %{has_metadata: false} = Bookmarks.parse_site_query("metadata:pending")
      assert %{has_metadata: false} = Bookmarks.parse_site_query("-metadata:has")
      assert %{has_metadata: nil} = Bookmarks.parse_site_query("metadata:whatever")
      assert %{has_metadata: nil} = Bookmarks.parse_site_query("hello world")
    end

    test "search_sites/3 filters by metadata presence" do
      user = AccountsFixtures.user_fixture()

      {:ok, enriched} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/enriched",
          "display_name" => "Enriched",
          "created_by_id" => user.id,
          "tags" => []
        })

      {:ok, pending} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/pending",
          "display_name" => "Pending",
          "created_by_id" => user.id,
          "tags" => []
        })

      {:ok, _} =
        Bookmarks.update_site(enriched, %{
          "crawled_at" => DateTime.utc_now(),
          "tags" => []
        })

      ids_with = fn query ->
        page =
          Bookmarks.search_sites(
            user.id,
            Bookmarks.parse_site_query(query),
            page: 1,
            page_size: 50
          )

        MapSet.new(page.entries, & &1.id)
      end

      assert ids_with.("metadata:has") |> MapSet.equal?(MapSet.new([enriched.id]))
      assert ids_with.("metadata:missing") |> MapSet.equal?(MapSet.new([pending.id]))
    end

    test "search_sites/3 surfaces fuzzy phrase matches against the title" do
      user = AccountsFixtures.user_fixture()

      {:ok, partial} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/a",
          "display_name" => "the art",
          "created_by_id" => user.id,
          "tags" => []
        })

      {:ok, full} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/b",
          "display_name" => "the art of programming",
          "created_by_id" => user.id,
          "tags" => []
        })

      {:ok, offers} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/c",
          "display_name" => "the art offers",
          "created_by_id" => user.id,
          "tags" => []
        })

      {:ok, _unrelated} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/d",
          "display_name" => "cooking class",
          "created_by_id" => user.id,
          "tags" => []
        })

      parsed = Bookmarks.parse_site_query("the art of")
      page = Bookmarks.search_sites(user.id, parsed, page: 1, page_size: 50)

      ids = Enum.map(page.entries, & &1.id) |> MapSet.new()
      assert MapSet.subset?(MapSet.new([partial.id, full.id, offers.id]), ids)
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

      page = Bookmarks.list_domains(user.id)
      assert page.total_entries == 1

      assert [
               %{
                 domain: "example.com",
                 count: 2,
                 tags: [%{name: "docs", count: 2}, %{name: "elixir", count: 1}]
               }
             ] = page.entries
    end
  end
end
