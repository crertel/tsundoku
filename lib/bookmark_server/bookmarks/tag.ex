defmodule BookmarkServer.Bookmarks.Tag do
  use BookmarkServer.Schema
  import Ecto.Changeset
  alias BookmarkServer.Bookmarks.Site
  alias BookmarkServer.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tags" do
    field :name, :string

    many_to_many :sites, Site,  join_through: "sites_tags", on_replace: :delete

    belongs_to :created_by, User

    timestamps()
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> BookmarkServer.Repo.preload(:created_by)
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> put_assoc(:created_by, Map.get(attrs, "created_by", []))
  end
end
