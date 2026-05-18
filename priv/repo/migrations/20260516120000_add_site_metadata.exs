defmodule BookmarkServer.Repo.Migrations.AddSiteMetadata do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :description, :text
      add :favicon_url, :text
      add :og_image_url, :text
      add :metadata_fetched_at, :utc_datetime_usec
    end
  end
end
