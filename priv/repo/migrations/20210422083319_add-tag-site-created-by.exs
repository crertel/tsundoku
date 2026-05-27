defmodule :"Elixir.Tsundoku.Repo.Migrations.Add-tag-site-created-by" do
  use Ecto.Migration

  def change do
    alter table(:tags) do
      add :created_by_id, references(:users, type: :uuid)
    end

    alter table(:sites) do
      add :created_by_id, references(:users, type: :uuid)
    end

    create(index(:sites, [:created_by_id]))
    create(index(:tags, [:created_by_id]))

    create(unique_index(:sites, [:url, :created_by_id], name: :site_url_created_by_unique_index))
    create(unique_index(:tags, [:name, :created_by_id], name: :tag_name_created_by_unique_index))
  end
end
