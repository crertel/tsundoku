defmodule Tsundoku.Repo.Migrations.CreateSites do
  use Ecto.Migration

  def change do
    create table(:sites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :url, :text
      add :display_name, :text, default: ""

      timestamps()
    end

    create table(:sites_tags, primary_key: false) do
      add :tag_id, references(:tags, type: :uuid, on_delete: :delete_all)
      add :site_id, references(:sites, type: :uuid, on_delete: :delete_all)
    end

    create(index(:sites_tags, [:tag_id]))
    create(index(:sites_tags, [:site_id]))
  end
end
