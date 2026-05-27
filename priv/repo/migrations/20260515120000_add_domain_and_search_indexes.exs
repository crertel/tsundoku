defmodule Tsundoku.Repo.Migrations.AddDomainAndSearchIndexes do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    alter table(:sites) do
      add :domain, :text
    end

    execute """
    UPDATE sites
    SET domain = regexp_replace(
      lower(substring(url from '^[a-zA-Z]+://([^/?#]+)')),
      '^www\\.', ''
    )
    WHERE url IS NOT NULL
    """

    create index(:sites, [:created_by_id, :domain])
    create index(:sites, [:created_by_id, :inserted_at])

    drop index(:sites_tags, [:site_id])
    create index(:sites_tags, [:site_id, :tag_id])

    execute "CREATE INDEX tags_created_by_lower_name_index ON tags (created_by_id, lower(name))"

    execute "CREATE INDEX sites_url_trgm_index ON sites USING GIN (lower(url) gin_trgm_ops)"

    execute """
    CREATE INDEX sites_display_name_trgm_index
    ON sites USING GIN (lower(display_name) gin_trgm_ops)
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS sites_display_name_trgm_index"
    execute "DROP INDEX IF EXISTS sites_url_trgm_index"
    execute "DROP INDEX IF EXISTS tags_created_by_lower_name_index"
    drop index(:sites_tags, [:site_id, :tag_id])
    create index(:sites_tags, [:site_id])
    drop index(:sites, [:created_by_id, :inserted_at])
    drop index(:sites, [:created_by_id, :domain])

    alter table(:sites) do
      remove :domain
    end
  end
end
