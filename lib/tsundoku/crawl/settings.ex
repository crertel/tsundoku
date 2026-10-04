defmodule Tsundoku.Crawl.Settings do
  @moduledoc """
  Server-wide crawler settings. There is at most one row; see
  `Tsundoku.Crawl.get_settings/0` for the defaults used before one exists.
  """

  use Tsundoku.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "crawl_settings" do
    # How many pages are fetched at once, across all domains.
    field :concurrency, :integer, default: 5
    # How long to leave a domain alone after fetching a page from it.
    field :delay_ms, :integer, default: 1_000
    # How long to wait for a page before giving up on it.
    field :timeout_ms, :integer, default: 10_000
    field :paused, :boolean, default: false

    timestamps()
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:concurrency, :delay_ms, :timeout_ms, :paused])
    |> validate_required([:concurrency, :delay_ms, :timeout_ms, :paused])
    |> validate_number(:concurrency, greater_than_or_equal_to: 1, less_than_or_equal_to: 20)
    |> validate_number(:delay_ms, greater_than_or_equal_to: 0, less_than_or_equal_to: 60_000)
    |> validate_number(:timeout_ms,
      greater_than_or_equal_to: 1_000,
      less_than_or_equal_to: 60_000
    )
    |> unique_constraint(:singleton)
  end
end
