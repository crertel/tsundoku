defmodule :"Elixir.BookmarkServer.Repo.Migrations.Add-tag-site-created-by" do
  use Ecto.Migration

  def change do
    alter table(:tags) do
      add :created_by, references(:users, type: :uuid)
    end

    alter table(:sites) do
      add :created_by, references(:users, type: :uuid)
    end

    create(index(:sites, [:created_by]))
    create(index(:tags, [:created_by]))
  end
end
