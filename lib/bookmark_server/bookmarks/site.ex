defmodule BookmarkServer.Bookmarks.Site do
  use BookmarkServer.Schema
  import Ecto.Changeset
  alias BookmarkServer.Bookmarks.Tag

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sites" do
    field :url, :string
    many_to_many :tags, Tag,  join_through: "sites_tags", on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(site, attrs) do
    site
    |> BookmarkServer.Repo.preload(:tags)
    |> cast(attrs, [:url])
    |> validate_required([:url])
    |> put_assoc(:tags, Map.get(attrs, "tags", []))
  end
end
