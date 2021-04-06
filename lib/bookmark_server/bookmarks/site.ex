defmodule BookmarkServer.Bookmarks.Site do
  use BookmarkServer.Schema
  import Ecto.Changeset
  alias BookmarkServer.Bookmarks.Tag

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sites" do
    field :url, :string

    many_to_many :tags, Tag,  join_through: "sites_tags"

    timestamps()
  end

  @doc false
  def changeset(site, attrs) do
    site
    |> cast(attrs, [:url])
    |> validate_required([:url])
  end
end
