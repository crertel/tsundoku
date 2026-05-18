defmodule BookmarkServer.Repo.Migrations.RenameMetadataToCrawl do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE sites RENAME COLUMN metadata_fetched_at TO crawled_at"
    execute "ALTER TABLE sites RENAME COLUMN metadata_status TO crawl_status"

    execute """
    ALTER INDEX sites_created_by_id_metadata_status_index
      RENAME TO sites_created_by_id_crawl_status_index
    """
  end

  def down do
    execute """
    ALTER INDEX sites_created_by_id_crawl_status_index
      RENAME TO sites_created_by_id_metadata_status_index
    """

    execute "ALTER TABLE sites RENAME COLUMN crawl_status TO metadata_status"
    execute "ALTER TABLE sites RENAME COLUMN crawled_at TO metadata_fetched_at"
  end
end
