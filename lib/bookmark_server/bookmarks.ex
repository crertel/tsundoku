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
  def list_tags do
    Repo.all(Tag)
  end

  def paginate_tags(params \\ []) do
    Tag
    |> Repo.paginate(params)
  end

  def search_and_paginate_tags( %{
    search_string: search_string
  }, params \\ [] ) do
    q_string = "%#{search_string}%"
    q = from t in Tag,
        where: ilike(t.name, ^q_string)

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
  def get_tag!(id), do: Repo.get!(Tag, id)

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
    Repo.all(Site)
  end

  def paginate_sites(params \\ []) do
    q = from s in Site, preload: [:tags]
    Repo.paginate(q, params)
  end

  def search_and_paginate_sites( %{
    search_string: search_string,
    filtering_tags: filtering_tags
  }, params \\ []) do

    page_size = Keyword.get(params, :page_size)
    {page_number, _} = Keyword.get(params, :page, "1") |> Integer.parse()

    tags_query = from t in Tag, order_by: t.name

    q_string = "%#{search_string}%"
    site_query = from s in Site,
        join: t in assoc(s, :tags),
        where: ilike(s.display_name, ^q_string)

    q = Enum.reduce(filtering_tags, site_query, fn(tag,full_query) ->
      tag_query = from s in Site,
        join: t in assoc(s, :tags),
        where: ^tag == t.name
      intersect(tag_query, ^full_query)
    end)

    final_query = q |> distinct(true)
    offset = (page_number-1) * page_size
    entry_count = Repo.all(final_query) |> Enum.count()
    entries = final_query
              |> preload([tags: ^tags_query])
              |> offset( ^offset)
              |> limit(^page_size)
              |> Repo.all()

    %Scrivener.Page{
      page_size: page_size,
      page_number: page_number,
      entries: entries,
      total_entries: entry_count,
      total_pages: trunc(:math.ceil( entry_count / page_size))
    }
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

  def load_urls(tags, urls) do
    # preload tags into DB
    :ok = tags |> Enum.each( fn( tag ) ->
      try do
        %Tag{}
        |> Tag.changeset(%{"name" => tag})
        |> BookmarkServer.Repo.insert!()
      rescue
        _ -> nil
      end
    end)

    loaded_tags = BookmarkServer.Repo.all(Tag)
                  |> Enum.reduce(%{}, fn tag, loaded_tags ->
                    Map.put(loaded_tags, tag.name, tag)
                  end)

    # load URLs into DB
    :ok =  Enum.each(urls, fn {bm_tags, bm_url,bm_title} ->
      try do
        fetched_tags = Enum.map( bm_tags, &(loaded_tags[&1]))

        %Site{}
        |> BookmarkServer.Bookmarks.Site.changeset(%{
          "url" => bm_url,
          "display_name" => bm_title,
          "tags" => fetched_tags
          })
        |> BookmarkServer.Repo.insert!()
      rescue
        _ ->nil
      end
    end)
  end

  def import_from_file(path) do
    file = File.read!(path)
    clean_html = clean_html(file)
    root_nodes = Floki.parse_document!(clean_html)
                 |> Enum.filter( fn
                    {"dl",_,_} -> true
                    _ -> false
                  end)

    urls = root_nodes |> Enum.map( &parse_node(&1,[])) |> List.flatten
    tags = urls |> Enum.reduce(MapSet.new(), fn {tags, _url, _title}, tag_set ->
      MapSet.new(tags)
      |> MapSet.union(tag_set)
    end)
    {:ok, tags, urls}
  end

  def clean_html(html) do
    html
    |> String.replace(~r/<p>/i,"")
    |> String.replace(~r/<\/p>/i, "")
    |> String.replace(~r/<dt>/i,"")
    |> String.replace(~r/<hr>/i,"")
    |> String.replace(~r/icon=".*?"/i,"")
    |> String.replace(~r/icon_uri=".*?"/i,"")
    |> String.replace(~r/add_date=".*?"/i,"")
    |> String.replace(~r/last_modified=".*?"/i,"")
  end

  def parse_node( {_,_,kids}, governing_tags) do
    %{urls: urls} =
      Enum.reduce(kids,
      %{tags: governing_tags, urls: []},
      fn(
        {"dl", _attrs, _kids} = knode, %{tags: tags, urls: urls} = state) ->
          newurls = parse_node(knode, tags)
          [_newtag | oldtags] = tags # we pop off the head tag, since that was added by the `h3` case
          %{state | urls: newurls ++ urls, tags: oldtags}

        {"a", attrs, [title]}, %{tags: tags, urls: urls} = state ->
          {"href", url} = List.keyfind(attrs, "href", 0)
          %{state | urls: [{tags, url, title } | urls]}

        {"h3", _attrs, [label]}, %{tags: tags} = state ->
          %{state | tags: [label | tags]}
    end)
    urls # goal here is to return a list of { [tag1, tag2, tag3...], url, label} tuples
  end

end
