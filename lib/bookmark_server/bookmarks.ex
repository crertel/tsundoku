defmodule BookmarkServer.Bookmarks do
  @moduledoc """
  The Bookmarks context.
  """

  import Ecto.Query, warn: false
  alias BookmarkServer.Repo

  alias BookmarkServer.Bookmarks.Tag
  alias BookmarkServer.Bookmarks.Site

  @doc """
  Returns the list of tags.

  ## Examples

      iex> list_tags()
      [%Tag{}, ...]

  """
  @spec list_tags() :: [Tag.t()]
  def list_tags do
    Repo.all(Tag)
  end

  def paginate_tags(params \\ []) do
    Tag
    |> Repo.paginate(params)
  end

  def search_and_paginate_tags(
        %{
          search_string: search_string,
          created_by: user_id
        },
        params \\ []
      ) do
    q_string = "%#{search_string}%"

    q =
      from t in Tag,
        where: ilike(t.name, ^q_string),
        where: ^user_id == t.created_by_id,
        order_by: [asc: t.name]

    Repo.paginate(q, params)
  end

  @doc """
  Gets a single tag.

  Raises `Ecto.NoResultsError` if the Tag does not exist.

  ## Examples

      iex> get_tag!(123)
      %Tag{}

      iex> get_tag!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_tag!(Tag.id_t()) :: Tag.t() | no_return()

  def get_tag!(id), do: Repo.get!(Tag, id)

  def get_tag(id), do: Repo.get(Tag, id)

  @doc """
  Creates a tag.

  ## Examples

      iex> create_tag(%{field: value})
      {:ok, %Tag{}}

      iex> create_tag(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_tag(attrs \\ %{}) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a tag.

  ## Examples

      iex> update_tag(tag, %{field: new_value})
      {:ok, %Tag{}}

      iex> update_tag(tag, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a tag.

  ## Examples

      iex> delete_tag(tag)
      {:ok, %Tag{}}

      iex> delete_tag(tag)
      {:error, %Ecto.Changeset{}}

  """
  def delete_tag(%Tag{} = tag) do
    Repo.delete(tag)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking tag changes.

  ## Examples

      iex> change_tag(tag)
      %Ecto.Changeset{data: %Tag{}}

  """
  def change_tag(%Tag{} = tag, attrs \\ %{}) do
    Tag.changeset(tag, attrs)
  end

  def get_tag_by_name(name) do
    Repo.get_by(Tag, name: name)
  end

  alias BookmarkServer.Bookmarks.Site

  @doc """
  Returns the list of sites.

  ## Examples

      iex> list_sites()
      [%Site{}, ...]

  """
  def list_sites do
    q = from s in Site, preload: [:tags]
    Repo.all(q)
  end

  def paginate_sites(params \\ []) do
    q = from s in Site, preload: [:tags]
    Repo.paginate(q, params)
  end

  def list_domains(created_by) do
    Site
    |> where([s], s.created_by_id == ^created_by)
    |> preload(:tags)
    |> Repo.all()
    |> Enum.reduce(%{}, fn site, domains ->
      case domain_from_url(site.url) do
        nil ->
          domains

        domain ->
          domain_data =
            Map.get(domains, domain, %{
              domain: domain,
              count: 0,
              tags: %{}
            })

          tags =
            Enum.reduce(site.tags, domain_data.tags, fn tag, tag_counts ->
              Map.update(tag_counts, tag.name, 1, &(&1 + 1))
            end)

          Map.put(domains, domain, %{domain_data | count: domain_data.count + 1, tags: tags})
      end
    end)
    |> Map.values()
    |> Enum.map(fn domain ->
      tags =
        domain.tags
        |> Enum.map(fn {name, count} -> %{name: name, count: count} end)
        |> Enum.sort_by(&{String.downcase(&1.name), &1.name})

      %{domain | tags: tags}
    end)
    |> Enum.sort_by(&{-&1.count, &1.domain})
  end

  def list_domain_names(created_by) do
    created_by
    |> list_domains()
    |> Enum.map(& &1.domain)
  end

  defp domain_from_url(url) do
    case URI.parse(url || "") do
      %URI{host: host} when is_binary(host) ->
        host
        |> String.downcase()
        |> String.replace_prefix("www.", "")

      _ ->
        nil
    end
  end

  def parse_site_query(query) do
    query
    |> tokenize_site_query()
    |> Enum.reduce(
      %{
        text: [],
        tags: [],
        domains: [],
        urls: [],
        exclude_tags: [],
        exclude_domains: [],
        exclude_urls: []
      },
      &parse_site_query_token/2
    )
  end

  def search_and_paginate_sites(query_params, params \\ [])

  def search_and_paginate_sites(
        %{
          query: query,
          created_by: created_by
        },
        params
      ) do
    page_size = Keyword.get(params, :page_size)
    {page_number, _} = "#{Keyword.get(params, :page, "1")}" |> Integer.parse()
    parsed_query = parse_site_query(query)

    entries =
      Site
      |> where([s], s.created_by_id == ^created_by)
      |> preload(:tags)
      |> Repo.all()
      |> Enum.filter(&site_matches_query?(&1, parsed_query))

    offset = (page_number - 1) * page_size
    page_entries = entries |> Enum.drop(offset) |> Enum.take(page_size)

    %Scrivener.Page{
      page_size: page_size,
      page_number: page_number,
      entries: page_entries,
      total_entries: length(entries),
      total_pages: trunc(:math.ceil(length(entries) / page_size))
    }
  end

  def search_and_paginate_sites(
        %{
          search_string: search_string,
          filtering_tags: filtering_tags,
          created_by: created_by
        },
        params
      ) do
    query =
      [search_string | Enum.map(filtering_tags, &query_fragment("tag", &1))]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")

    search_and_paginate_sites(%{query: query, created_by: created_by}, params)
  end

  def query_fragment(field, value) do
    value = to_string(value)

    if String.contains?(value, ~s(")) or String.match?(value, ~r/\s/) do
      ~s(#{field}:"#{String.replace(value, ~s("), ~s(\\"))}")
    else
      "#{field}:#{value}"
    end
  end

  defp tokenize_site_query(query) do
    ~r/-?(?:tag|domain|site|url):"[^"]*"|-?(?:tag|domain|site|url):\S+|"[^"]*"|\S+/
    |> Regex.scan(query || "")
    |> List.flatten()
  end

  @doc """
  Removes the first filter token of the given type/value from a query string.

  Type is one of `"text"`, `"tag"`, `"domain"`, or `"url"`. Value comparison is
  case-insensitive and ignores quoting. Negated filters (prefixed `-`) are not
  considered, since the visible filter pills only show included filters.
  """
  def remove_filter(query, type, value) do
    target = String.downcase(value)

    query
    |> tokenize_site_query()
    |> Enum.reduce({[], false}, fn token, {acc, removed} ->
      cond do
        removed -> {[token | acc], true}
        filter_token_matches?(token, type, target) -> {acc, true}
        true -> {[token | acc], false}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join(" ")
  end

  defp filter_token_matches?(token, "text", target) do
    not Regex.match?(~r/^-?(?:tag|domain|site|url):/, token) and
      String.downcase(normalize_query_value(token)) == target
  end

  defp filter_token_matches?(token, type, target) when type in ["tag", "domain", "url"] do
    fields = if type == "domain", do: ["domain", "site"], else: [type]

    case Regex.run(~r/^(tag|domain|site|url):(?:"([^"]*)"|(.+))$/, token) do
      [_, field, quoted] ->
        field in fields and
          String.downcase(normalize_query_value(quoted)) == target

      [_, field, quoted, raw] ->
        if field in fields do
          token_value = if quoted == "", do: raw, else: quoted
          String.downcase(normalize_query_value(token_value)) == target
        else
          false
        end

      _ ->
        false
    end
  end

  defp parse_site_query_token(token, query) do
    case Regex.run(~r/^(-?)(tag|domain|site|url):(?:"([^"]*)"|(.+))$/, token) do
      [_, negation, field, quoted_value] ->
        parsed_value = normalize_query_value(quoted_value)
        put_fielded_query_value(query, negation, field, parsed_value)

      [_, negation, field, quoted_value, value] ->
        parsed_value =
          normalize_query_value(if(quoted_value == "", do: value, else: quoted_value))

        put_fielded_query_value(query, negation, field, parsed_value)

      _ ->
        value = normalize_query_value(token)
        if value == "", do: query, else: %{query | text: query.text ++ [String.downcase(value)]}
    end
  end

  defp normalize_query_value(nil), do: ""

  defp normalize_query_value(value) do
    value
    |> String.trim()
    |> String.trim_leading(~s("))
    |> String.trim_trailing(~s("))
  end

  defp put_fielded_query_value(query, _negation, _field, ""), do: query

  defp put_fielded_query_value(query, "-", "tag", value),
    do: %{query | exclude_tags: query.exclude_tags ++ [String.downcase(value)]}

  defp put_fielded_query_value(query, "-", field, value) when field in ["domain", "site"],
    do: %{query | exclude_domains: query.exclude_domains ++ [normalize_domain_filter(value)]}

  defp put_fielded_query_value(query, "-", "url", value),
    do: %{query | exclude_urls: query.exclude_urls ++ [String.downcase(value)]}

  defp put_fielded_query_value(query, _, "tag", value),
    do: %{query | tags: query.tags ++ [String.downcase(value)]}

  defp put_fielded_query_value(query, _, field, value) when field in ["domain", "site"],
    do: %{query | domains: query.domains ++ [normalize_domain_filter(value)]}

  defp put_fielded_query_value(query, _, "url", value),
    do: %{query | urls: query.urls ++ [String.downcase(value)]}

  defp normalize_domain_filter(value) do
    value
    |> String.downcase()
    |> String.replace_prefix("www.", "")
  end

  defp site_matches_query?(site, query) do
    searchable_text =
      [site.display_name, site.url, domain_from_url(site.url)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    tag_names = Enum.map(site.tags, &String.downcase(&1.name))
    domain = domain_from_url(site.url)
    url = String.downcase(site.url || "")

    Enum.all?(query.text, &String.contains?(searchable_text, &1)) and
      Enum.all?(query.tags, &(&1 in tag_names)) and
      Enum.all?(query.urls, &String.contains?(url, &1)) and
      Enum.all?(query.domains, &domain_matches?(domain, &1)) and
      Enum.all?(query.exclude_tags, &(&1 not in tag_names)) and
      Enum.all?(query.exclude_urls, &(not String.contains?(url, &1))) and
      Enum.all?(query.exclude_domains, &(not domain_matches?(domain, &1)))
  end

  defp domain_matches?(nil, _filter), do: false
  defp domain_matches?(_domain, ""), do: true

  defp domain_matches?(domain, filter) do
    domain == filter or String.ends_with?(domain, ".#{filter}")
  end

  @doc """
  Gets a single site.

  Raises `Ecto.NoResultsError` if the Site does not exist.

  ## Examples

      iex> get_site!(123)
      %Site{}

      iex> get_site!(456)
      ** (Ecto.NoResultsError)

  """
  def get_site!(id), do: Repo.get!(Site, id)

  def get_site(id), do: Repo.get(Site, id)

  @spec create_site(%{optional(:__struct__) => none, optional(atom | binary) => any}) :: any
  @doc """
  Creates a site.

  ## Examples

      iex> create_site(%{field: value})
      {:ok, %Site{}}

      iex> create_site(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_site(attrs \\ %{}) do
    %Site{}
    |> Site.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a site.

  ## Examples

      iex> update_site(site, %{field: new_value})
      {:ok, %Site{}}

      iex> update_site(site, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_site(%Site{} = site, attrs) do
    site
    |> Site.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a site.

  ## Examples

      iex> delete_site(site)
      {:ok, %Site{}}

      iex> delete_site(site)
      {:error, %Ecto.Changeset{}}

  """
  def delete_site(%Site{} = site) do
    Repo.delete(site)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking site changes.

  ## Examples

      iex> change_site(site)
      %Ecto.Changeset{data: %Site{}}

  """
  def change_site(%Site{} = site, attrs \\ %{}) do
    Site.changeset(site, attrs)
  end

  def load_urls(tags, urls, creator_id) do
    # preload tags into DB
    :ok =
      tags
      |> Enum.each(fn tag ->
        try do
          %Tag{}
          |> Tag.changeset(%{"name" => tag, "created_by_id" => creator_id})
          |> BookmarkServer.Repo.insert!()
        rescue
          _ -> nil
        end
      end)

    loaded_tags =
      BookmarkServer.Repo.all(Tag)
      |> Enum.reduce(%{}, fn tag, loaded_tags ->
        Map.put(loaded_tags, tag.name, tag)
      end)

    # load URLs into DB
    :ok =
      Enum.each(urls, fn {bm_tags, bm_url, bm_title} ->
        try do
          fetched_tags = Enum.map(bm_tags, &loaded_tags[&1])

          %Site{}
          |> BookmarkServer.Bookmarks.Site.changeset(%{
            "url" => bm_url,
            "display_name" => bm_title,
            "tags" => fetched_tags,
            "created_by_id" => creator_id
          })
          |> BookmarkServer.Repo.insert!()
        rescue
          _ -> nil
        end
      end)
  end

  def import_from_file(path) do
    file = File.read!(path)
    clean_html = clean_html(file)

    root_nodes =
      Floki.parse_document!(clean_html)
      |> Enum.filter(fn
        {"dl", _, _} -> true
        _ -> false
      end)

    urls = root_nodes |> Enum.map(&parse_node(&1, [])) |> List.flatten()

    tags =
      urls
      |> Enum.reduce(MapSet.new(), fn {tags, _url, _title}, tag_set ->
        MapSet.new(tags)
        |> MapSet.union(tag_set)
      end)

    {:ok, tags, urls}
  end

  def clean_html(html) do
    html
    |> String.replace(~r/<p>/i, "")
    |> String.replace(~r/<\/p>/i, "")
    |> String.replace(~r/<dt>/i, "")
    |> String.replace(~r/<hr>/i, "")
    |> String.replace(~r/icon=".*?"/i, "")
    |> String.replace(~r/icon_uri=".*?"/i, "")
    |> String.replace(~r/add_date=".*?"/i, "")
    |> String.replace(~r/last_modified=".*?"/i, "")
  end

  def parse_node({_, _, kids}, governing_tags) do
    %{urls: urls} =
      Enum.reduce(
        kids,
        %{tags: governing_tags, urls: []},
        fn
          {"dl", _attrs, _kids} = knode, %{tags: tags, urls: urls} = state ->
            newurls = parse_node(knode, tags)
            # we pop off the head tag, since that was added by the `h3` case
            [_newtag | oldtags] = tags
            %{state | urls: newurls ++ urls, tags: oldtags}

          {"a", attrs, [title]}, %{tags: tags, urls: urls} = state ->
            {"href", url} = List.keyfind(attrs, "href", 0)
            %{state | urls: [{tags, url, title} | urls]}

          {"h3", _attrs, [label]}, %{tags: tags} = state ->
            %{state | tags: [label | tags]}
        end
      )

    # goal here is to return a list of { [tag1, tag2, tag3...], url, label} tuples
    urls
  end
end
