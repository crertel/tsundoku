# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     BookmarkServer.Repo.insert!(%BookmarkServer.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias BookmarkServer.Accounts
alias BookmarkServer.Accounts.User
alias BookmarkServer.Repo

admin_email = "admin@localhost"
admin_password = "adminpassword"

case Accounts.get_user_by_email(admin_email) do
  nil ->
    {:ok, user} =
      Accounts.register_user(%{
        email: admin_email,
        password: admin_password
      })

    user
    |> User.confirm_changeset()
    |> Repo.update!()

    IO.puts("Seeded #{admin_email} / #{admin_password}")

  _user ->
    IO.puts("Seed user #{admin_email} already exists")
end
