defmodule Tsundoku.Repo.Migrations.AddSiteMetadataStatus do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :metadata_status, :string
    end

    create index(:sites, [:created_by_id, :metadata_status])
  end
end
