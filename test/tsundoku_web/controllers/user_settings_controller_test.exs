defmodule TsundokuWeb.UserSettingsControllerTest do
  use TsundokuWeb.ConnCase, async: true

  alias Tsundoku.Accounts
  alias Tsundoku.Bookmarks
  import Tsundoku.AccountsFixtures

  setup :register_and_log_in_user

  describe "GET /users/settings" do
    test "renders settings page", %{conn: conn} do
      conn = get(conn, Routes.user_settings_path(conn, :edit))
      response = html_response(conn, 200)
      assert response =~ "<h1>Settings</h1>"
    end

    test "redirects if user is not logged in" do
      conn = build_conn()
      conn = get(conn, Routes.user_settings_path(conn, :edit))
      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end
  end

  describe "PUT /users/settings (change password form)" do
    test "updates the user password and resets tokens", %{conn: conn, user: user} do
      new_password_conn =
        put(conn, Routes.user_settings_path(conn, :update), %{
          "action" => "update_password",
          "current_password" => valid_user_password(),
          "user" => %{
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(new_password_conn) == Routes.user_settings_path(conn, :edit)
      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "does not update password on invalid data", %{conn: conn} do
      old_password_conn =
        put(conn, Routes.user_settings_path(conn, :update), %{
          "action" => "update_password",
          "current_password" => "invalid",
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      response = html_response(old_password_conn, 200)
      assert response =~ "<h1>Settings</h1>"
      assert response =~ "should be at least 12 character(s)"
      assert response =~ "does not match password"
      assert response =~ "is not valid"

      assert get_session(old_password_conn, :user_token) == get_session(conn, :user_token)
    end
  end

  describe "PUT /users/settings (change email form)" do
    @tag :capture_log
    test "updates the user email", %{conn: conn, user: user} do
      conn =
        put(conn, Routes.user_settings_path(conn, :update), %{
          "action" => "update_email",
          "current_password" => valid_user_password(),
          "user" => %{"email" => unique_user_email()}
        })

      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(user.email)
    end

    test "does not update email on invalid data", %{conn: conn} do
      conn =
        put(conn, Routes.user_settings_path(conn, :update), %{
          "action" => "update_email",
          "current_password" => "invalid",
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "<h1>Settings</h1>"
      assert response =~ "must have the @ sign and no spaces"
      assert response =~ "is not valid"
    end
  end

  describe "GET /users/settings/confirm_email/:token" do
    setup %{user: user} do
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{token: token, email: email}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      conn = get(conn, Routes.user_settings_path(conn, :confirm_email, token))
      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Email changed successfully"
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      conn = get(conn, Routes.user_settings_path(conn, :confirm_email, token))
      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      conn = get(conn, Routes.user_settings_path(conn, :confirm_email, "oops"))
      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Email change link is invalid or it has expired"

      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      conn = get(conn, Routes.user_settings_path(conn, :confirm_email, token))
      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end
  end

  describe "PUT /users/settings (empty account form)" do
    setup %{user: user} do
      {:ok, tag} = Bookmarks.create_tag(%{"name" => "mine", "created_by_id" => user.id})

      {:ok, _} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/mine",
          "created_by_id" => user.id,
          "tags" => [tag]
        })

      :ok
    end

    defp empty_account(conn, params) do
      put(
        conn,
        Routes.user_settings_path(conn, :update),
        Map.put(params, "action", "empty_account")
      )
    end

    test "deletes the user's bookmarks and tags but keeps the login", %{conn: conn, user: user} do
      conn =
        empty_account(conn, %{
          "current_password" => valid_user_password(),
          "confirm_email" => " #{user.email} "
        })

      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Emptied account: 1 bookmarks and 1 tags deleted."

      assert Bookmarks.count_user_sites(user.id) == 0
      assert Bookmarks.list_user_tags(user.id) == []
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "refuses with the wrong password", %{conn: conn, user: user} do
      conn = empty_account(conn, %{"current_password" => "nope", "confirm_email" => user.email})

      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Wrong password."
      assert Bookmarks.count_user_sites(user.id) == 1
    end

    test "refuses when the confirmation email doesn't match", %{conn: conn, user: user} do
      conn =
        empty_account(conn, %{
          "current_password" => valid_user_password(),
          "confirm_email" => "someone-else@example.com"
        })

      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Confirmation email didn't match."
      assert Bookmarks.count_user_sites(user.id) == 1
    end
  end

  describe "PUT /users/settings (deactivate account form)" do
    defp deactivate(conn, params) do
      put(
        conn,
        Routes.user_settings_path(conn, :update),
        Map.put(params, "action", "deactivate_account")
      )
    end

    test "deletes the user and their data and logs out", %{conn: conn, user: user} do
      {:ok, site} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/mine",
          "created_by_id" => user.id,
          "tags" => []
        })

      conn =
        deactivate(conn, %{
          "current_password" => valid_user_password(),
          "confirm_email" => user.email
        })

      assert redirected_to(conn) == "/"
      refute get_session(conn, :user_token)
      refute Accounts.get_user_by_email(user.email)
      refute Bookmarks.get_site(site.id)
    end

    test "leaves other users alone", %{conn: conn, user: user} do
      other = user_fixture()

      {:ok, theirs} =
        Bookmarks.create_site(%{
          "url" => "https://example.com/theirs",
          "created_by_id" => other.id,
          "tags" => []
        })

      deactivate(conn, %{
        "current_password" => valid_user_password(),
        "confirm_email" => user.email
      })

      assert Accounts.get_user_by_email(other.email)
      assert Bookmarks.get_site(theirs.id)
    end

    test "refuses with the wrong password", %{conn: conn, user: user} do
      conn = deactivate(conn, %{"current_password" => "nope", "confirm_email" => user.email})

      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Wrong password."
      assert Accounts.get_user_by_email(user.email)
    end

    test "refuses when the confirmation email doesn't match", %{conn: conn, user: user} do
      conn =
        deactivate(conn, %{
          "current_password" => valid_user_password(),
          "confirm_email" => ""
        })

      assert redirected_to(conn) == Routes.user_settings_path(conn, :edit)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Confirmation email didn't match."
      assert Accounts.get_user_by_email(user.email)
    end
  end
end
