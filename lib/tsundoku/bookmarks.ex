defmodule Tsundoku.Bookmarks do
  @moduledoc """
  The Bookmarks context.

  Mutation functions (`create_site`, `update_site`, `delete_site`,
  `create_tag`, `update_tag`, `delete_tag`, `delete_sites_for_tag`,
  `bulk_insert_imported`) broadcast a tiny ID-only event on the owning
  user's PubSub topic so open LiveView pages can react. Subscribe with
  `Tsundoku.Bookmarks.subscribe(user_id)`; messages are shaped
  `{:bookmarks_event, kind, id_or_payload}`. `Metadata.enrich` writes
  directly via the schema (not via this module) so background metadata
  fetches stay quiet, by design.
  """

  import Ecto.Query, warn: false
  alias Tsundoku.Repo

  alias Tsundoku.Bookmarks.Tag
  alias Tsundoku.Bookmarks.Site
  alias Tsundoku.Bookmarks.SavedSearch

  @doc """
  PubSub topic used to broadcast bookmark/tag mutations for a user.
  """
  def topic(user_id) when is_binary(user_id), do: "user:#{user_id}:bookmarks"

  @doc """
  Subscribes the calling process to `user_id`'s bookmarks topic.
  """
  def subscribe(user_id) when is_binary(user_id) do
    Phoenix.PubSub.subscribe(Tsundoku.PubSub, topic(user_id))
  end

  defp broadcast(nil, _kind, _payload), do: :ok

  defp broadcast(user_id, kind, payload) when is_binary(user_id) do
    Phoenix.PubSub.broadcast(
      Tsundoku.PubSub,
      topic(user_id),
      {:bookmarks_event, kind, payload}
    )

    :ok
  end

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

  Pair every callsite with `TsundokuWeb.LiveHelpers.ensure_owner!/2`
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
    result =
      %Tag{}
      |> Tag.changeset(attrs)
      |> Repo.insert()

    with {:ok, tag} <- result do
      broadcast(tag.created_by_id, :tag_created, tag.id)
    end

    result
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
    result =
      tag
      |> Tag.changeset(attrs)
      |> Repo.update()

    with {:ok, updated} <- result do
      broadcast(updated.created_by_id, :tag_updated, updated.id)
    end

    result
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
    result = Repo.delete(tag)

    with {:ok, _} <- result do
      broadcast(tag.created_by_id, :tag_deleted, tag.id)
    end

    result
  end

  @doc """
  Deletes every site owned by `tag.created_by_id` that carries `tag`.
  Does not delete the tag itself (so the empty tag remains for re-use).
  Caller must verify ownership. Returns `{deleted_count, nil}`.
  """
  def delete_sites_for_tag(%Tag{id: tag_id, created_by_id: user_id}) do
    site_ids =
      from(st in "sites_tags",
        join: s in Site,
        on: s.id == st.site_id,
        where:
          st.tag_id == type(^tag_id, :binary_id) and
            s.created_by_id == ^user_id,
        select: s.id
      )
      |> Repo.all()

    result =
      from(s in Site, where: s.id in ^site_ids)
      |> Repo.delete_all()

    # Single summary event — caller may have nuked thousands of sites.
    if site_ids != [], do: broadcast(user_id, :bulk_changed, %{sites_deleted: length(site_ids)})

    result
  end

  @doc """
  Deletes every site and every tag owned by the user, in a single
  transaction. Sites are deleted first so their `sites_tags` rows
  cascade off; tags are then deleted. Returns
  `{:ok, %{sites_deleted, tags_deleted}}`.
  """
  def empty_user_data(%Tsundoku.Accounts.User{id: user_id}) do
    result =
      Repo.transaction(fn ->
        {sites_deleted, _} =
          from(s in Site, where: s.created_by_id == ^user_id)
          |> Repo.delete_all()

        {tags_deleted, _} =
          from(t in Tag, where: t.created_by_id == ^user_id)
          |> Repo.delete_all()

        %{sites_deleted: sites_deleted, tags_deleted: tags_deleted}
      end)

    with {:ok, counts} <- result do
      broadcast(user_id, :bulk_changed, counts)
    end

    result
  end

  @doc """
  Counts the user's sites tagged with the given tag.
  """
  def count_sites_for_tag(%Tag{id: tag_id, created_by_id: user_id}) do
    from(st in "sites_tags",
      join: s in Site,
      on: s.id == st.site_id,
      where: st.tag_id == type(^tag_id, :binary_id) and s.created_by_id == ^user_id,
      select: count()
    )
    |> Repo.one()
  end

  @doc """
  Returns the number of sites tagged `tag` per calendar month for the
  user, sorted ascending by month. Months with zero saves are omitted —
  the renderer is responsible for filling gaps if a regular series is
  needed. Each entry is `%{month: ~D[YYYY-MM-01], count: n}`.
  """
  def site_count_by_month_for_tag(%Tag{id: tag_id, created_by_id: user_id}) do
    from(st in "sites_tags",
      join: s in Site,
      on: s.id == st.site_id,
      where:
        st.tag_id == type(^tag_id, :binary_id) and
          s.created_by_id == ^user_id,
      group_by: fragment("date_trunc('month', ?)", s.inserted_at),
      order_by: fragment("date_trunc('month', ?)", s.inserted_at),
      select: %{
        month: fragment("date_trunc('month', ?)::date", s.inserted_at),
        count: count(s.id)
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns the tags that most frequently appear alongside `tag` on the
  user's sites, sorted by descending co-occurrence count. Each entry is
  `%{id, name, count}`. Limited to `opts[:limit]` (default 20).
  """
  def list_co_occurring_tags(%Tag{id: tag_id, created_by_id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    from(st1 in "sites_tags",
      join: s in Site,
      on: s.id == st1.site_id and s.created_by_id == ^user_id,
      join: st2 in "sites_tags",
      on: st2.site_id == st1.site_id and st2.tag_id != st1.tag_id,
      join: t in Tag,
      on: t.id == st2.tag_id,
      where: st1.tag_id == type(^tag_id, :binary_id),
      group_by: [t.id, t.name],
      order_by: [desc: count(t.id), asc: t.name],
      limit: ^limit,
      select: %{id: t.id, name: t.name, count: count(t.id)}
    )
    |> Repo.all()
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

  alias Tsundoku.Bookmarks.Site

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

      iex> Tsundoku.Bookmarks.enqueue_metadata_backfill()
      iex> Tsundoku.Bookmarks.enqueue_metadata_backfill(force: true)
      iex> Tsundoku.Bookmarks.enqueue_metadata_backfill(user_id: user.id)
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
      |> Tsundoku.Workers.EnrichMetadata.new()
      |> Oban.insert!()
    end)

    length(ids)
  end

  @doc """
  Returns a paginated `Scrivener.Page` of the user's domains with
  per-domain tag counts. Each entry is `%{domain, count, tags: [%{name,
  count}]}` (sorted by descending count, then domain name).

  Options:
    * `:page` (default `1`) — 1-indexed page number.
    * `:page_size` (default `50`).
    * `:search` (default `""`) — case-insensitive substring filter on
      `sites.domain`.

  The page-sized totals query and the tag-counts query only operate
  over the matching slice (totals are LIMIT/OFFSET'd at the DB; tag
  counts are restricted to the domains being rendered this page).
  """
  def list_domains(created_by, opts \\ []) do
    page = opts |> Keyword.get(:page, 1) |> coerce_page()
    page_size = Keyword.get(opts, :page_size, 50)
    search = opts |> Keyword.get(:search, "") |> to_string() |> String.trim()
    sort = Keyword.get(opts, :sort, :count)

    base =
      from s in Site,
        where: s.created_by_id == ^created_by and not is_nil(s.domain)

    base =
      if search == "" do
        base
      else
        pattern = "%" <> escape_like(String.downcase(search)) <> "%"
        from s in base, where: ilike(s.domain, ^pattern)
      end

    total_entries =
      from(s in base, select: count(s.domain, :distinct))
      |> Repo.one()

    page_totals =
      base
      |> group_by([s], s.domain)
      |> domain_order_by(sort)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> select([s], {s.domain, count(s.id)})
      |> Repo.all()

    page_domain_names = Enum.map(page_totals, fn {d, _} -> d end)

    tag_counts =
      if page_domain_names == [] do
        []
      else
        from(s in Site,
          join: st in "sites_tags",
          on: st.site_id == s.id,
          join: t in Tag,
          on: t.id == st.tag_id,
          where:
            s.created_by_id == ^created_by and
              s.domain in ^page_domain_names,
          group_by: [s.domain, t.name],
          select: {s.domain, t.name, count()}
        )
        |> Repo.all()
      end

    tags_by_domain =
      Enum.reduce(tag_counts, %{}, fn {domain, name, count}, acc ->
        Map.update(acc, domain, [%{name: name, count: count}], fn existing ->
          [%{name: name, count: count} | existing]
        end)
      end)

    entries =
      Enum.map(page_totals, fn {domain, count} ->
        tags =
          tags_by_domain
          |> Map.get(domain, [])
          |> Enum.sort_by(&{String.downcase(&1.name), &1.name})

        %{domain: domain, count: count, tags: tags}
      end)

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

  defp domain_order_by(query, :alpha), do: order_by(query, [s], asc: s.domain)

  defp domain_order_by(query, _count),
    do: order_by(query, [s], desc: count(s.id), asc: s.domain)

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
    sort = Keyword.get(opts, :sort, :recency)

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
      |> order_sites(all_titles, sort)
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

  defp order_sites(query, _titles, :alpha) do
    from s in query, order_by: [asc: s.display_name, asc: s.url]
  end

  defp order_sites(query, [], :recency) do
    order_by(query, [s], desc: s.inserted_at)
  end

  defp order_sites(query, titles, :recency) do
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
  Total count of a user's saved sites, unfiltered.
  """
  def count_user_sites(user_id) do
    from(s in Site, where: s.created_by_id == ^user_id, select: count())
    |> Repo.one()
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

  # Field names match in any case (phone keyboards capitalise the first
  # word) and come out lowercased, so everything downstream of the
  # tokenizer only has to know the lowercase spelling.
  defp tokenize_site_query(query) do
    ~r/-?(?:tag|domain|site|url|title|metadata|status):"[^"]*"|-?(?:tag|domain|site|url|title|metadata|status):\S+|"[^"]*"|\S+/i
    |> Regex.scan(query || "")
    |> List.flatten()
    |> Enum.map(&downcase_field_name/1)
  end

  defp downcase_field_name(token) do
    Regex.replace(
      ~r/^(-?)(tag|domain|site|url|title|metadata|status):/i,
      token,
      fn _, negation, field -> negation <> String.downcase(field) <> ":" end
    )
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
        {_token, _idx}, {found, true} ->
          {found, true}

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

  defp bare_token?(token),
    do: not Regex.match?(~r/^-?(?:tag|domain|site|url|title|metadata|status):/, token)

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

  Pair every callsite with `TsundokuWeb.LiveHelpers.ensure_owner!/2`
  (or an equivalent check against `created_by_id`) so a user can't reach
  another user's site by guessing the UUID. Raises `Ecto.NoResultsError`
  if the site does not exist.
  """
  def get_site!(id), do: Repo.get!(Site, id)

  @doc """
  Returns a random site owned by `user_id`, or `nil` if the user has
  none. Uses `ORDER BY RANDOM() LIMIT 1` — fine at personal scale; if a
  user ever hits hundreds of thousands of sites, swap to an offset
  approach.
  """
  def random_user_site(user_id) do
    from(s in Site,
      where: s.created_by_id == ^user_id,
      order_by: fragment("RANDOM()"),
      limit: 1
    )
    |> Repo.one()
  end

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
      {:ok, site} ->
        Tsundoku.Metadata.enrich_async(site)
        broadcast(site.created_by_id, :site_created, site.id)

      _ ->
        :ok
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
      {{:ok, updated}, true} -> Tsundoku.Metadata.enrich_async(updated)
      _ -> :ok
    end

    with {:ok, updated} <- result do
      broadcast(updated.created_by_id, :site_updated, updated.id)
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
    result = Repo.delete(site)

    with {:ok, _} <- result do
      broadcast(site.created_by_id, :site_deleted, site.id)
    end

    result
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

  @bulk_insert_chunk 500

  @doc """
  Bulk-imports parsed bookmark records using `Repo.insert_all` with
  `on_conflict: :nothing`, so re-imports are idempotent on the
  `(url, created_by_id)` / `(name, created_by_id)` unique indexes.

  `url_records` is a list of maps `%{"tags" => [name, ...], "url" =>
  url, "title" => title}` (string-keyed because this is called from the
  Oban worker after JSON round-trip). `progress_fn` is invoked after
  each chunk with `%{processed: n, stage: :sites}`.

  Returns `%{sites_inserted: n, tags_inserted: m}`.
  """
  def bulk_insert_imported(tag_names, url_records, user_id, progress_fn \\ fn _ -> :ok end) do
    now = DateTime.utc_now()

    tag_rows =
      tag_names
      |> Enum.uniq()
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.map(fn name ->
        %{
          id: Ecto.UUID.generate(),
          name: name,
          created_by_id: user_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    {tags_inserted, _} =
      Repo.insert_all(Tag, tag_rows,
        on_conflict: :nothing,
        conflict_target: [:name, :created_by_id]
      )

    # Tag and Site IDs are stored as Postgres uuid (binary). The
    # `sites_tags` join table uses raw insert_all (no schema), so it
    # needs binary UUIDs — keep them in binary form in this lookup.
    tag_id_by_name =
      from(t in Tag, where: t.created_by_id == ^user_id, select: {t.name, t.id})
      |> Repo.all()
      |> Map.new(fn {name, id} -> {name, Ecto.UUID.dump!(id)} end)

    progress_fn.(%{processed: 0, stage: :sites})

    sites_inserted =
      url_records
      |> Stream.reject(fn r ->
        url = Map.get(r, "url")
        is_nil(url) or url == ""
      end)
      |> Stream.chunk_every(@bulk_insert_chunk)
      |> Enum.reduce({0, 0}, fn chunk, {processed, inserted_acc} ->
        site_rows =
          Enum.map(chunk, fn %{"url" => url, "title" => title} ->
            %{
              id: Ecto.UUID.generate(),
              url: url,
              display_name: title || "",
              domain: derive_domain(url),
              created_by_id: user_id,
              inserted_at: now,
              updated_at: now
            }
          end)

        {_count, inserted_sites} =
          Repo.insert_all(Site, site_rows,
            on_conflict: :nothing,
            conflict_target: [:url, :created_by_id],
            returning: [:id, :url]
          )

        inserted_id_by_url =
          Map.new(inserted_sites, &{&1.url, Ecto.UUID.dump!(&1.id)})

        join_rows =
          Enum.flat_map(chunk, fn %{"tags" => bm_tags, "url" => url} ->
            case Map.get(inserted_id_by_url, url) do
              nil ->
                []

              site_id_bin ->
                bm_tags
                |> Enum.uniq()
                |> Enum.flat_map(fn tag_name ->
                  case Map.get(tag_id_by_name, tag_name) do
                    nil -> []
                    tag_id_bin -> [%{site_id: site_id_bin, tag_id: tag_id_bin}]
                  end
                end)
            end
          end)

        if join_rows != [] do
          Repo.insert_all("sites_tags", join_rows)
        end

        Enum.each(inserted_sites, fn s ->
          %{site_id: s.id}
          |> Tsundoku.Workers.EnrichMetadata.new()
          |> Oban.insert()
        end)

        new_processed = processed + length(chunk)
        new_inserted = inserted_acc + length(inserted_sites)
        progress_fn.(%{processed: new_processed, stage: :sites})
        {new_processed, new_inserted}
      end)
      |> elem(1)

    summary = %{sites_inserted: sites_inserted, tags_inserted: tags_inserted}
    broadcast(user_id, :bulk_changed, summary)
    summary
  end

  defp derive_domain(url) do
    case URI.parse(url || "") do
      %URI{host: host} when is_binary(host) ->
        host |> String.downcase() |> String.replace_prefix("www.", "")

      _ ->
        nil
    end
  end

  @backup_version 1

  @doc """
  Returns a serializable map of every site and tag owned by `user`,
  suitable for `Jason.encode!/1`. Idempotent restore relies on
  `(url, created_by_id)` and `(name, created_by_id)` uniqueness.
  """
  def export_user(%Tsundoku.Accounts.User{id: user_id, email: email}) do
    tags =
      from(t in Tag,
        where: t.created_by_id == ^user_id,
        order_by: t.name,
        select: %{name: t.name, description: t.description}
      )
      |> Repo.all()

    sites =
      from(s in Site,
        where: s.created_by_id == ^user_id,
        order_by: s.inserted_at,
        preload: :tags
      )
      |> Repo.all()
      |> Enum.map(fn s ->
        %{
          url: s.url,
          display_name: s.display_name,
          notes: s.notes,
          description: s.description,
          favicon_url: s.favicon_url,
          favicon_data_b64: if(s.favicon_data, do: Base.encode64(s.favicon_data), else: nil),
          favicon_content_type: s.favicon_content_type,
          og_image_url: s.og_image_url,
          crawled_at: s.crawled_at && DateTime.to_iso8601(s.crawled_at),
          crawl_status: s.crawl_status,
          inserted_at: s.inserted_at && DateTime.to_iso8601(s.inserted_at),
          tags: Enum.map(s.tags, & &1.name)
        }
      end)

    %{
      version: @backup_version,
      exported_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      user_email: email,
      tags: tags,
      sites: sites
    }
  end

  @doc """
  Idempotently imports a backup map (as produced by `export_user/1`) into
  the given user's data. Tags missing for the user are created. Sites
  missing for the user are created. Sites that already exist (by URL)
  are *left alone*, but their tag set is unioned with the dump's tags
  (so re-restoring after re-tagging doesn't lose tags). Tags are
  reattached by name. Returns
  `{:ok, %{tags_created, sites_created, sites_skipped}}`.
  """
  def restore_user(%Tsundoku.Accounts.User{id: user_id}, %{} = dump) do
    case Map.get(dump, "version") || Map.get(dump, :version) do
      v when v in [1, "1"] -> do_restore(user_id, dump)
      other -> {:error, {:unsupported_version, other}}
    end
  end

  defp do_restore(user_id, dump) do
    dump_tags = Map.get(dump, "tags") || Map.get(dump, :tags) || []
    dump_sites = Map.get(dump, "sites") || Map.get(dump, :sites) || []

    Repo.transaction(fn ->
      tags_created =
        Enum.reduce(dump_tags, 0, fn t, acc ->
          name = Map.get(t, "name") || Map.get(t, :name)
          description = Map.get(t, "description") || Map.get(t, :description)

          case get_user_tag_by_name(name, user_id) do
            %Tag{} ->
              acc

            nil ->
              %Tag{}
              |> Tag.changeset(%{
                name: name,
                description: description,
                created_by_id: user_id
              })
              |> Repo.insert!()

              acc + 1
          end
        end)

      tag_by_name =
        from(t in Tag, where: t.created_by_id == ^user_id, select: {t.name, t})
        |> Repo.all()
        |> Map.new()

      {sites_created, sites_skipped} =
        Enum.reduce(dump_sites, {0, 0}, fn s, {created, skipped} ->
          url = Map.get(s, "url") || Map.get(s, :url)
          tag_names = Map.get(s, "tags") || Map.get(s, :tags) || []
          tag_records = Enum.map(tag_names, &Map.get(tag_by_name, &1)) |> Enum.reject(&is_nil/1)

          case get_user_bookmark_by_url(url, user_id) do
            nil ->
              attrs =
                s
                |> stringify_keys()
                |> Map.put("created_by_id", user_id)
                |> Map.put("tags", tag_records)
                |> decode_favicon()
                |> Map.drop(["favicon_data_b64", "inserted_at"])

              %Site{}
              |> Site.changeset(attrs)
              |> Repo.insert!()

              {created + 1, skipped}

            %Site{} = existing ->
              existing = Repo.preload(existing, :tags)
              merged = Enum.uniq_by(existing.tags ++ tag_records, & &1.id)

              existing
              |> Site.changeset(%{"tags" => merged})
              |> Repo.update!()

              {created, skipped + 1}
          end
        end)

      %{
        tags_created: tags_created,
        sites_created: sites_created,
        sites_skipped: sites_skipped
      }
    end)
  end

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      kv -> kv
    end)
  end

  defp decode_favicon(%{"favicon_data_b64" => b64} = attrs) when is_binary(b64) do
    case Base.decode64(b64) do
      {:ok, bin} -> Map.put(attrs, "favicon_data", bin)
      :error -> attrs
    end
  end

  defp decode_favicon(attrs), do: attrs

  # ----- Saved searches -----

  @doc "Lists a user's saved searches alphabetically by name."
  def list_user_saved_searches(user_id) do
    from(s in SavedSearch, where: s.created_by_id == ^user_id, order_by: s.name)
    |> Repo.all()
  end

  def get_saved_search!(id), do: Repo.get!(SavedSearch, id)

  def get_saved_search_by_token(token) when is_binary(token) do
    case Ecto.UUID.cast(token) do
      {:ok, uuid} -> Repo.get_by(SavedSearch, feed_token: uuid)
      :error -> nil
    end
  end

  def change_saved_search(%SavedSearch{} = ss, attrs \\ %{}) do
    SavedSearch.changeset(ss, attrs)
  end

  def create_saved_search(attrs) do
    %SavedSearch{}
    |> SavedSearch.changeset(attrs)
    |> Repo.insert()
  end

  def update_saved_search(%SavedSearch{} = ss, attrs) do
    ss
    |> SavedSearch.changeset(attrs)
    |> Repo.update()
  end

  def delete_saved_search(%SavedSearch{} = ss), do: Repo.delete(ss)

  @doc "Generates a fresh UUID feed_token and persists it."
  def enable_feed(%SavedSearch{} = ss) do
    token = Ecto.UUID.generate()

    ss
    |> SavedSearch.feed_token_changeset(token)
    |> Repo.update()
  end

  @doc "Revokes the feed_token (nulls it out)."
  def disable_feed(%SavedSearch{} = ss) do
    ss
    |> SavedSearch.feed_token_changeset(nil)
    |> Repo.update()
  end

  @doc """
  Reuses the site search pipeline to fetch the most recent N sites
  matching a saved search. Used by the Atom renderer.
  """
  def search_results_for_feed(%SavedSearch{} = ss, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    parsed = parse_site_query(ss.query)
    %{entries: entries} = search_sites(ss.created_by_id, parsed, page: 1, page_size: limit)
    entries
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
