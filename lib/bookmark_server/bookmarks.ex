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
  Moves every site tagged `source` onto `dest`, then deletes `source`.
  Sites that already carry `dest` just lose `source`. Runs in a single
  transaction. Callers should verify ownership of both tags before
  calling.

  Returns `{:ok, %{source_name, dest_name, moved}}` on success.
  """
  def merge_tags(%Tag{id: id}, %Tag{id: id}), do: {:error, :same_tag}

  def merge_tags(%Tag{} = source, %Tag{} = dest) do
    Repo.transaction(fn ->
      moved =
        from(st in "sites_tags",
          where: st.tag_id == type(^source.id, :binary_id)
        )
        |> Repo.aggregate(:count, :site_id)

      # Add the dest tag to every site that has source but not dest, in
      # one INSERT … SELECT so Ecto's type/2 casts handle the UUIDs.
      insert_query =
        from st in "sites_tags",
          where: st.tag_id == type(^source.id, :binary_id),
          where:
            st.site_id not in subquery(
              from(st2 in "sites_tags",
                where: st2.tag_id == type(^dest.id, :binary_id),
                select: st2.site_id
              )
            ),
          select: %{tag_id: type(^dest.id, :binary_id), site_id: st.site_id}

      Repo.insert_all("sites_tags", insert_query)

      # FK is set to on_delete: :delete_all, so dropping the source tag
      # cascades to its sites_tags rows.
      Repo.delete!(source)

      %{source_name: source.name, dest_name: dest.name, moved: moved}
    end)
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

  @doc """
  Looks up a site by URL, scoped to the given user. Returns `nil` if no
  match exists. Backed by the unique `sites(url, created_by_id)` index.
  """
  def get_user_bookmark_by_url(url, user_id) do
    Repo.get_by(Site, url: url, created_by_id: user_id)
  end

  alias BookmarkServer.Bookmarks.Site

  @doc """
  Returns every site in the system across all users. NOT scoped to the
  current user — only for admin/maintenance code paths. For user-facing
  reads, use `search_sites/3`.
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
  Enqueues a metadata-enrichment job for every matching site. Returns the
  number of jobs enqueued. By default skips sites that already have
  `crawled_at` set; pass `force: true` to re-enrich everything.
  Pass `user_id: ...` to scope to one user.

  Intended for backfills (e.g. after deploying a fetcher change) and for
  ad-hoc re-runs from a remote shell.

      iex> BookmarkServer.Bookmarks.enqueue_metadata_backfill()
      iex> BookmarkServer.Bookmarks.enqueue_metadata_backfill(force: true)
      iex> BookmarkServer.Bookmarks.enqueue_metadata_backfill(user_id: user.id)
  """
  def enqueue_metadata_backfill(opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    force = Keyword.get(opts, :force, false)

    query = from(s in Site, select: s.id)

    query =
      if force, do: query, else: from(s in query, where: is_nil(s.crawled_at))

    query =
      if user_id, do: from(s in query, where: s.created_by_id == ^user_id), else: query

    ids = Repo.all(query)

    Enum.each(ids, fn id ->
      %{site_id: id}
      |> BookmarkServer.Workers.EnrichMetadata.new()
      |> Oban.insert!()
    end)

    length(ids)
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

  def parse_site_query(query) do
    initial = %{
      bare_phrase: "",
      bare_tokens: [],
      titles: [],
      tags: [],
      domains: [],
      urls: [],
      has_metadata: nil,
      crawl_status: nil,
      exclude_titles: [],
      exclude_tags: [],
      exclude_domains: [],
      exclude_urls: []
    }

    parsed =
      query
      |> tokenize_site_query()
      |> Enum.reduce(initial, &parse_site_query_token/2)

    bare_phrase = parsed.bare_tokens |> Enum.join(" ") |> String.trim()

    parsed
    |> Map.put(:bare_phrase, bare_phrase)
    |> Map.delete(:bare_tokens)
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

    all_titles = title_filters_for(parsed_query)

    query =
      base
      |> filter_by_titles(all_titles, :include)
      |> filter_by_titles(parsed_query.exclude_titles, :exclude)
      |> filter_by_url(parsed_query.urls, :include)
      |> filter_by_url(parsed_query.exclude_urls, :exclude)
      |> filter_by_domain(parsed_query.domains, :include)
      |> filter_by_domain(parsed_query.exclude_domains, :exclude)
      |> filter_by_tag(parsed_query.tags, :include)
      |> filter_by_tag(parsed_query.exclude_tags, :exclude)
      |> filter_by_metadata(parsed_query.has_metadata)
      |> filter_by_status(parsed_query.crawl_status)

    total_entries = Repo.aggregate(query, :count, :id)

    entries =
      query
      |> order_titles(all_titles)
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

  defp order_titles(query, []), do: order_by(query, [s], desc: s.inserted_at)

  defp order_titles(query, titles) do
    phrase = Enum.join(titles, " ")

    from s in query,
      order_by: [
        desc: fragment("word_similarity(lower(?), lower(?))", ^phrase, s.display_name),
        desc: s.inserted_at
      ]
  end

  defp title_filters_for(%{bare_phrase: "", titles: titles}), do: titles
  defp title_filters_for(%{bare_phrase: bare, titles: titles}), do: [bare | titles]

  defp coerce_page(value) when is_integer(value), do: max(value, 1)

  defp coerce_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n >= 1 -> n
      _ -> 1
    end
  end

  defp coerce_page(_), do: 1

  defp filter_by_titles(query, [], _direction), do: query

  defp filter_by_titles(query, phrases, :include) do
    Enum.reduce(phrases, query, fn phrase, q ->
      from s in q,
        where: fragment("lower(?) <% lower(?)", ^phrase, s.display_name)
    end)
  end

  defp filter_by_titles(query, phrases, :exclude) do
    Enum.reduce(phrases, query, fn phrase, q ->
      from s in q,
        where: fragment("NOT (lower(?) <% lower(?))", ^phrase, s.display_name)
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

  defp filter_by_metadata(query, nil), do: query

  defp filter_by_metadata(query, true),
    do: from(s in query, where: not is_nil(s.crawled_at))

  defp filter_by_metadata(query, false),
    do: from(s in query, where: is_nil(s.crawled_at))

  defp filter_by_status(query, nil), do: query

  defp filter_by_status(query, "failed") do
    from s in query,
      where: not is_nil(s.crawl_status) and s.crawl_status != "ok"
  end

  defp filter_by_status(query, status) do
    from s in query, where: s.crawl_status == ^status
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
    parsed = parse_site_query(query)
    search_sites(created_by, parsed, params)
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
    ~r/-?(?:tag|domain|site|url|title|metadata|status):"[^"]*"|-?(?:tag|domain|site|url|title|metadata|status):\S+|"[^"]*"|\S+/
    |> Regex.scan(query || "")
    |> List.flatten()
  end

  @doc """
  Removes a filter from a query string. Type is one of `"title"`, `"tag"`,
  `"domain"`, or `"url"`. Value comparison is case-insensitive and ignores
  quoting. Negated filters (prefixed `-`) are not considered, since the
  visible filter pills only show included filters.

  For `"title"`, removes either a matching `title:VAL` token *or* the
  collected bare tokens whose joined phrase equals the value (whichever is
  present). For the other types, removes the first matching field token.
  """
  def remove_filter(query, "metadata", _value) do
    query
    |> tokenize_site_query()
    |> Enum.reject(&Regex.match?(~r/^-?metadata:/, &1))
    |> Enum.join(" ")
  end

  def remove_filter(query, "status", _value) do
    query
    |> tokenize_site_query()
    |> Enum.reject(&Regex.match?(~r/^-?status:/, &1))
    |> Enum.join(" ")
  end

  def remove_filter(query, "title", value) do
    target = String.downcase(value)
    tokens = tokenize_site_query(query)

    {field_match_index, _} =
      tokens
      |> Enum.with_index()
      |> Enum.reduce({nil, false}, fn
        {_token, _idx}, {found, true} -> {found, true}
        {token, idx}, {nil, false} ->
          if title_field_token_matches?(token, target),
            do: {idx, true},
            else: {nil, false}
      end)

    if field_match_index do
      tokens |> List.delete_at(field_match_index) |> Enum.join(" ")
    else
      bare_target = bare_phrase_of(tokens) |> String.downcase()

      if bare_target == target do
        tokens
        |> Enum.reject(&bare_token?/1)
        |> Enum.join(" ")
      else
        Enum.join(tokens, " ")
      end
    end
  end

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

  defp bare_token?(token), do: not Regex.match?(~r/^-?(?:tag|domain|site|url|title):/, token)

  defp bare_phrase_of(tokens) do
    tokens
    |> Enum.filter(&bare_token?/1)
    |> Enum.map(&normalize_query_value/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp title_field_token_matches?(token, target) do
    case Regex.run(~r/^title:(?:"([^"]*)"|(.+))$/, token) do
      [_, quoted] ->
        String.downcase(normalize_query_value(quoted)) == target

      [_, quoted, raw] ->
        token_value = if quoted == "", do: raw, else: quoted
        String.downcase(normalize_query_value(token_value)) == target

      _ ->
        false
    end
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
    case Regex.run(
           ~r/^(-?)(tag|domain|site|url|title|metadata|status):(?:"([^"]*)"|(.+))$/,
           token
         ) do
      [_, negation, field, quoted_value] ->
        parsed_value = normalize_query_value(quoted_value)
        put_fielded_query_value(query, negation, field, parsed_value)

      [_, negation, field, quoted_value, value] ->
        parsed_value =
          normalize_query_value(if(quoted_value == "", do: value, else: quoted_value))

        put_fielded_query_value(query, negation, field, parsed_value)

      _ ->
        value = normalize_query_value(token)

        if value == "" do
          query
        else
          %{query | bare_tokens: query.bare_tokens ++ [value]}
        end
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

  defp put_fielded_query_value(query, "-", "title", value),
    do: %{query | exclude_titles: query.exclude_titles ++ [value]}

  defp put_fielded_query_value(query, _, "tag", value),
    do: %{query | tags: query.tags ++ [String.downcase(value)]}

  defp put_fielded_query_value(query, _, field, value) when field in ["domain", "site"],
    do: %{query | domains: query.domains ++ [normalize_domain_filter(value)]}

  defp put_fielded_query_value(query, _, "url", value),
    do: %{query | urls: query.urls ++ [String.downcase(value)]}

  defp put_fielded_query_value(query, _, "title", value),
    do: %{query | titles: query.titles ++ [value]}

  defp put_fielded_query_value(query, "-", "metadata", value),
    do: put_metadata_filter(query, value, :invert)

  defp put_fielded_query_value(query, _, "metadata", value),
    do: put_metadata_filter(query, value, :keep)

  defp put_fielded_query_value(query, _, "status", value),
    do: %{query | crawl_status: normalize_status(value)}

  defp put_metadata_filter(query, value, polarity) do
    case metadata_value(value) do
      nil ->
        query

      bool ->
        bool = if polarity == :invert, do: not bool, else: bool
        %{query | has_metadata: bool}
    end
  end

  defp metadata_value(value) do
    case String.downcase(value) do
      v when v in ~w(has yes fetched true 1 done) -> true
      v when v in ~w(missing no pending false 0 none absent) -> false
      _ -> nil
    end
  end

  defp normalize_status(value) do
    v = value |> String.downcase() |> String.trim()

    cond do
      Regex.match?(~r/^\d{3}$/, v) -> "http_" <> v
      true -> v
    end
  end

  defp normalize_domain_filter(value) do
    value
    |> String.downcase()
    |> String.replace_prefix("www.", "")
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
    result =
      %Site{}
      |> Site.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, site} -> BookmarkServer.Metadata.enrich_async(site)
      _ -> :ok
    end

    result
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
    changeset = Site.changeset(site, attrs)
    url_changed? = match?(%{changes: %{url: _}}, changeset)
    result = Repo.update(changeset)

    case {result, url_changed?} do
      {{:ok, updated}, true} -> BookmarkServer.Metadata.enrich_async(updated)
      _ -> :ok
    end

    result
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
