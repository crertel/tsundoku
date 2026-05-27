defmodule Tsundoku.Repo.Migrations.InlineFavicons do
  use Ecto.Migration

  def up do
    alter table(:sites) do
      add :favicon_data, :bytea
      add :favicon_content_type, :string
    end

    flush()

    execute """
    UPDATE sites
       SET favicon_data         = f.data,
           favicon_content_type = f.content_type
      FROM favicons f
     WHERE sites.favicon_id = f.id
       AND f.data IS NOT NULL
    """

    drop index(:sites, [:favicon_id])

    alter table(:sites) do
      remove :favicon_id
    end

    drop table(:favicons)
  end

  def down do
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
      remove :favicon_data
      remove :favicon_content_type
    end

    create index(:sites, [:favicon_id])
  end
end
