defmodule BookmarkServer.Bookmarks do
  @moduledoc """
  The Bookmarks context.
  """

  import Ecto.Query, warn: false
  alias BookmarkServer.Repo

  alias BookmarkServer.Bookmarks.Tag
  alias BookmarkServer.Bookmarks.Site

  @doc """
  Returns every tag in the system across all users. NOT scoped to the
  current user — only use this for admin/maintenance code paths. For
  user-facing lookups, use `list_user_tags/1` or `list_user_tag_names/1`.
  """
  @spec list_global_tags() :: [Tag.t()]
  def list_global_tags do
    Repo.all(Tag)
  end

  @doc """
  Paginates every tag in the system across all users. NOT scoped — see
  `list_global_tags/0`. Use `search_and_paginate_tags/2` for user-scoped
  pagination.
  """
  def paginate_global_tags(params \\ []) do
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
  Gets a single tag by id, with no ownership check.

  Pair every callsite with `BookmarkServerWeb.LiveHelpers.ensure_owner!/2`
  (or an equivalent check against `created_by_id`) so a user can't reach
  another user's tag by guessing the UUID. Raises `Ecto.NoResultsError`
  if the tag does not exist.
  """
  @spec get_tag!(Tag.id_t()) :: Tag.t() | no_return()
  def get_tag!(id), do: Repo.get!(Tag, id)

  @doc """
  Gets a single tag by id, with no ownership check. See `get_tag!/1` —
  every callsite needs an explicit ownership check.
  """
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

  @doc """
  Looks up a tag by name across all users. NOT scoped — same-name tags
  are allowed per-user, so a global lookup can return another user's tag.
  Prefer `get_user_tag_by_name/2` for any code path that's about to
  associate the tag with the caller's data.
  """
  def get_global_tag_by_name(name) do
    Repo.get_by(Tag, name: name)
  end

  alias BookmarkServer.Bookmarks.Site

  @doc """
  Returns every site in the system across all users. NOT scoped to the
  current user — only for admin/maintenance code paths. For user-facing
  reads, use `search_sites/3` or `list_user_sites_with_tags/1`.
  """
  def list_global_sites do
    q = from s in Site, preload: [:tags]
    Repo.all(q)
  end

  @doc """
  Paginates every site in the system across all users. NOT scoped — see
  `list_global_sites/0`. Use `search_sites/3` for user-scoped pagination.
  """
  def paginate_global_sites(params \\ []) do
    q = from s in Site, preload: [:tags]
    Repo.paginate(q, params)
  end

  @doc """
  Groups a user's sites by domain with per-domain tag counts. Two indexed
  GROUP BY queries (one for totals, one for per-tag counts) — no in-memory
  aggregation over the full sites list.
  """
  def list_domains(created_by) do
    totals =
      from(s in Site,
        where: s.created_by_id == ^created_by and not is_nil(s.domain),
        group_by: s.domain,
        select: {s.domain, count(s.id)}
      )
      |> Repo.all()

    tag_counts =
      from(s in Site,
        join: st in "sites_tags",
        on: st.site_id == s.id,
        join: t in Tag,
        on: t.id == st.tag_id,
        where: s.created_by_id == ^created_by and not is_nil(s.domain),
        group_by: [s.domain, t.name],
        select: {s.domain, t.name, count()}
      )
      |> Repo.all()

    tags_by_domain =
      Enum.reduce(tag_counts, %{}, fn {domain, name, count}, acc ->
        Map.update(acc, domain, [%{name: name, count: count}], fn existing ->
          [%{name: name, count: count} | existing]
        end)
      end)

    totals
    |> Enum.map(fn {domain, count} ->
      tags =
        tags_by_domain
        |> Map.get(domain, [])
        |> Enum.sort_by(&{String.downcase(&1.name), &1.name})

      %{domain: domain, count: count, tags: tags}
    end)
    |> Enum.sort_by(&{-&1.count, &1.domain})
  end

  def list_domain_names(created_by) do
    list_user_domain_names(created_by)
  end

  @doc """
  Loads all of a user's sites with their tags preloaded. Use this when you
  need to both search and aggregate (e.g., to list domains) in the same
  request — pass the result to `search_and_paginate_loaded_sites/3` and
  `domains_from_sites/1` to avoid duplicate database hits.
  """
  def list_user_sites_with_tags(created_by) do
    Site
    |> where([s], s.created_by_id == ^created_by)
    |> preload(:tags)
    |> Repo.all()
  end

  @doc """
  Aggregates a preloaded list of sites into the same shape `list_domains/1`
  returns.
  """
  def domains_from_sites(sites) do
    sites
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

  @doc """
  Filters and paginates a user's sites in the database. Each part of a
  parsed query maps to a `WHERE` clause or a `sites_tags` subquery, so we
  never load the full table to filter in memory.
  """
  def search_sites(user_id, parsed_query, opts \\ []) do
    page = opts |> Keyword.get(:page, 1) |> coerce_page()
    page_size = Keyword.get(opts, :page_size, 50)

    base = from s in Site, where: s.created_by_id == ^user_id

    query =
      base
      |> filter_by_text(parsed_query.text)
      |> filter_by_url(parsed_query.urls, :include)
      |> filter_by_url(parsed_query.exclude_urls, :exclude)
      |> filter_by_domain(parsed_query.domains, :include)
      |> filter_by_domain(parsed_query.exclude_domains, :exclude)
      |> filter_by_tag(parsed_query.tags, :include)
      |> filter_by_tag(parsed_query.exclude_tags, :exclude)

    total_entries = Repo.aggregate(query, :count, :id)

    entries =
      query
      |> order_by([s], desc: s.inserted_at)
      |> preload(:tags)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> Repo.all()

    total_pages =
      if total_entries == 0, do: 0, else: trunc(:math.ceil(total_entries / page_size))

    %Scrivener.Page{
      page_size: page_size,
      page_number: page,
      entries: entries,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  defp coerce_page(value) when is_integer(value), do: max(value, 1)

  defp coerce_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n >= 1 -> n
      _ -> 1
    end
  end

  defp coerce_page(_), do: 1

  defp filter_by_text(query, []), do: query

  defp filter_by_text(query, terms) do
    Enum.reduce(terms, query, fn term, q ->
      pattern = "%" <> escape_like(term) <> "%"

      from s in q,
        where:
          ilike(s.display_name, ^pattern) or ilike(s.url, ^pattern) or
            ilike(coalesce(s.domain, ""), ^pattern)
    end)
  end

  defp filter_by_url(query, [], _direction), do: query

  defp filter_by_url(query, urls, direction) do
    Enum.reduce(urls, query, fn url, q ->
      pattern = "%" <> escape_like(url) <> "%"

      case direction do
        :include -> from s in q, where: ilike(s.url, ^pattern)
        :exclude -> from s in q, where: not ilike(s.url, ^pattern)
      end
    end)
  end

  defp filter_by_domain(query, [], _direction), do: query

  defp filter_by_domain(query, domains, direction) do
    Enum.reduce(domains, query, fn domain, q ->
      suffix = "%." <> escape_like(domain)

      case direction do
        :include ->
          from s in q,
            where: s.domain == ^domain or like(s.domain, ^suffix)

        :exclude ->
          from s in q,
            where: s.domain != ^domain and not like(coalesce(s.domain, ""), ^suffix)
      end
    end)
  end

  defp filter_by_tag(query, [], _direction), do: query

  defp filter_by_tag(query, tag_names, direction) do
    Enum.reduce(tag_names, query, fn name, q ->
      subq =
        from t in Tag,
          join: st in "sites_tags",
          on: st.tag_id == t.id,
          where: fragment("lower(?)", t.name) == ^name,
          select: st.site_id

      case direction do
        :include -> from s in q, where: s.id in subquery(subq)
        :exclude -> from s in q, where: s.id not in subquery(subq)
      end
    end)
  end

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @doc """
  Lists all distinct tag names owned by a user, sorted alphabetically.
  Used for the search autocomplete; small query, suitable to run on each
  render.
  """
  def list_user_tag_names(user_id) do
    from(t in Tag,
      where: t.created_by_id == ^user_id,
      order_by: t.name,
      select: t.name
    )
    |> Repo.all()
  end

  @doc """
  Lists `%Tag{}` structs owned by a user, sorted alphabetically. Used by
  the site form's tag autocomplete.
  """
  def list_user_tags(user_id) do
    from(t in Tag, where: t.created_by_id == ^user_id, order_by: t.name)
    |> Repo.all()
  end

  @doc """
  Fetches a tag by name, scoped to the given user. Returns `nil` if no
  matching tag exists for that user.
  """
  def get_user_tag_by_name(name, user_id) do
    Repo.get_by(Tag, name: name, created_by_id: user_id)
  end

  @doc """
  Lists all distinct domain names across a user's sites, sorted
  alphabetically. Uses the indexed `sites.domain` column.
  """
  def list_user_domain_names(user_id) do
    from(s in Site,
      where: s.created_by_id == ^user_id and not is_nil(s.domain),
      distinct: true,
      order_by: s.domain,
      select: s.domain
    )
    |> Repo.all()
  end

  def search_and_paginate_sites(query_params, params \\ [])

  def search_and_paginate_sites(
        %{
          query: query,
          created_by: created_by
        },
        params
      ) do
    created_by
    |> list_user_sites_with_tags()
    |> search_and_paginate_loaded_sites(query, params)
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

  @doc """
  Filters and paginates a preloaded list of sites. Use this together with
  `list_user_sites_with_tags/1` when the same request also needs to
  aggregate the list (e.g., domains).
  """
  def search_and_paginate_loaded_sites(sites, query, params) do
    page_size = Keyword.get(params, :page_size)
    {page_number, _} = "#{Keyword.get(params, :page, "1")}" |> Integer.parse()
    parsed_query = parse_site_query(query)

    entries = Enum.filter(sites, &site_matches_query?(&1, parsed_query))

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
  Gets a single site by id, with no ownership check.

  Pair every callsite with `BookmarkServerWeb.LiveHelpers.ensure_owner!/2`
  (or an equivalent check against `created_by_id`) so a user can't reach
  another user's site by guessing the UUID. Raises `Ecto.NoResultsError`
  if the site does not exist.
  """
  def get_site!(id), do: Repo.get!(Site, id)

  @doc """
  Gets a single site by id, with no ownership check. See `get_site!/1` —
  every callsite needs an explicit ownership check.
  """
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
