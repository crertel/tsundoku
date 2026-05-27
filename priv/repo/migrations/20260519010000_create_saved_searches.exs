defmodule Tsundoku.Repo.Migrations.CreateSavedSearches do
  use Ecto.Migration

  def change do
    create table(:saved_searches, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :created_by_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :query, :text, null: false, default: ""
      add :feed_token, :binary_id

      timestamps()
    end

    create unique_index(:saved_searches, [:created_by_id, :name],
             name: :saved_search_name_per_user_index
           )

    create unique_index(:saved_searches, [:feed_token], where: "feed_token IS NOT NULL")
    create index(:saved_searches, [:created_by_id])
  end
end
