defmodule Tsundoku.Repo.Migrations.AddSiteNotes do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :notes, :text
    end
  end
end
