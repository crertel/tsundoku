defmodule BookmarkServer.Repo.Migrations.AddFavicons do
  use Ecto.Migration

  def change do
    create table(:favicons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :url, :text, null: false
      add :data, :bytea
      add :content_type, :string
      add :crawled_at, :utc_datetime_usec
      add :crawl_status, :string

      timestamps()
    end

    create unique_index(:favicons, [:url])

    alter table(:sites) do
      add :favicon_id, references(:favicons, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:sites, [:favicon_id])
  end
end
