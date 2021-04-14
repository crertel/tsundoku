defmodule BookmarkServer.Bookmarks do
  @moduledoc """
  The Bookmarks context.
  """

  import Ecto.Query, warn: false
  alias BookmarkServer.Repo

  alias BookmarkServer.Bookmarks.Tag

  @doc """
  Returns the list of tags.

  ## Examples

      iex> list_tags()
      [%Tag{}, ...]

  """
  def list_tags do
    Repo.all(Tag)
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

  def import_from_file(path) do
    file = File.read!(path)
    clean_html = clean_html(file)

    root_nodes = Floki.parse_document!(clean_html)
                 |> Enum.filter( fn
                    {"dl",_,_} -> true
                    _ -> false
                  end)

    urls = List.last(root_nodes) |> parse_node([])

    tags = urls |> Enum.reduce(MapSet.new(), fn {tags, _url, _title}, tag_set ->
      tags
      |> MapSet.new()
      |> MapSet.union(tag_set)
    end )
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

  def floki_get_children( {_,_, kids}), do: kids
  def floki_get_children( _ ), do: []

  def floki_get_children_of_type( {_,_, kids}, type) do
    kids |> Enum.filter( fn
      {^type, _attrs, _kids} -> true
      _ -> false
    end)
  end
  def floki_get_children_of_type( _, _type) do
    []
  end



  def walk_floki_children( {_, _, _} = node, cb, 0) do
    cb.(node)
  end
  def walk_floki_children( node, cb, 0) do
    node
  end
  def walk_floki_children( {_, _, kids} = node, cb, depth) when depth > 0 do
    [cb.(node) | Enum.map(kids, &(walk_floki_children(&1,cb,depth-1)))]
  end

  def import_subtree(subtree) do

  end

end
