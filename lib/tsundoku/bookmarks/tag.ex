defmodule Tsundoku.Bookmarks.Tag do
  use Tsundoku.Schema
  import Ecto.Changeset
  alias Tsundoku.Bookmarks.Site
  alias Tsundoku.Accounts.User

  @type t() :: %__MODULE__{}
  @type id_t() :: String.t()

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tags" do
    field :name, :string
    field :description, :string

    many_to_many :sites, Site, join_through: "sites_tags", on_replace: :delete

    belongs_to :created_by, User

    timestamps()
  end

  @spec new() :: t()
  def new() do
    %__MODULE__{}
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :description, :created_by_id])
    |> validate_required([:name])
    |> unique_constraint(:name,
      name: :tag_name_created_by_unique_index,
      message: "you already have a tag with this name"
    )
  end
end
