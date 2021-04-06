defmodule BookmarkServer.Repo.Migrations.CreateSites do
  use Ecto.Migration

  def change do
    create table(:sites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :url, :string

      timestamps()
    end

    create table(:sites_tags) do
      add :tag_id, references(:tags, type: :uuid)
      add :site_id, references(:sites, type: :uuid)
    end

    unique_index(:sites_tags, [:tag_id, :site_id])
  end
end
