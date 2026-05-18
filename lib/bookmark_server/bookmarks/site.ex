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
    field :domain, :string
    field :description, :string
    field :favicon_url, :string
    field :og_image_url, :string
    field :crawled_at, :utc_datetime_usec
    field :crawl_status, :string

    many_to_many :tags, Tag, join_through: "sites_tags", on_replace: :delete

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
    |> cast(attrs, [
      :url,
      :display_name,
      :created_by_id,
      :description,
      :favicon_url,
      :og_image_url,
      :crawled_at,
      :crawl_status
    ])
    |> validate_required([:url])
    |> validate_url(:url)
    |> put_domain_from_url()
    |> put_assoc(:tags, Map.get(attrs, "tags", []))
  end

  defp put_domain_from_url(changeset) do
    case get_change(changeset, :url) do
      nil -> changeset
      url -> put_change(changeset, :domain, derive_domain(url))
    end
  end

  defp derive_domain(url) do
    case URI.parse(url || "") do
      %URI{host: host} when is_binary(host) ->
        host |> String.downcase() |> String.replace_prefix("www.", "")

      _ ->
        nil
    end
  end

  def validate_url(changeset, field, options \\ []) do
    validate_change(changeset, field, fn _, url ->
      if ValidUrl.validate(url), do: [], else: [{field, options[:message] || "Invalid URL"}]
    end)
  end
end
