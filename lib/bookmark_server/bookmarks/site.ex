defmodule BookmarkServer.Bookmarks.Site do
  use BookmarkServer.Schema
  import Ecto.Changeset
  alias BookmarkServer.Bookmarks.Tag
  alias BookmarkServer.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sites" do
    field :url, :string
    field :display_name, :string

    many_to_many :tags, Tag,  join_through: "sites_tags", on_replace: :delete

    belongs_to :created_by, User

    timestamps()
  end

  @spec changeset(nil | [%{optional(atom) => any}] | %{optional(atom) => any}, %{
          optional(:__struct__) => none,
          optional(atom | binary) => any
        }) :: Ecto.Changeset.t()
  @doc false
  def changeset(site, attrs) do
    site
    |> BookmarkServer.Repo.preload(:tags)
    |> cast(attrs, [:url, :display_name])
    |> validate_required([:url])
    |> put_assoc(:tags, Map.get(attrs, "tags", []))
  end
end
