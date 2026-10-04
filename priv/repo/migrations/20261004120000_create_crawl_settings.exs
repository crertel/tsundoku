defmodule Tsundoku.Repo.Migrations.CreateCrawlSettings do
  use Ecto.Migration

  def change do
    create table(:crawl_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Always true; the unique index on it keeps the table to one row.
      add :singleton, :boolean, null: false, default: true

      add :concurrency, :integer, null: false, default: 5
      add :delay_ms, :integer, null: false, default: 1_000
      add :timeout_ms, :integer, null: false, default: 10_000
      add :paused, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:crawl_settings, [:singleton])
  end
end
