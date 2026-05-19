defmodule BookmarkServer.Bookmarks.SavedSearch do
  use BookmarkServer.Schema
  import Ecto.Changeset
  alias BookmarkServer.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "saved_searches" do
    field :name, :string
    field :query, :string, default: ""
    field :feed_token, Ecto.UUID

    belongs_to :created_by, User

    timestamps()
  end

  def changeset(saved_search, attrs) do
    saved_search
    |> cast(attrs, [:name, :query, :created_by_id])
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> unique_constraint([:created_by_id, :name],
      name: :saved_search_name_per_user_index,
      message: "you already have a saved search with this name"
    )
  end

  def feed_token_changeset(saved_search, token) do
    saved_search
    |> change(feed_token: token)
  end
end
