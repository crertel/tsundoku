defmodule BookmarkServerWeb.UserSettingsController do
  use BookmarkServerWeb, :controller

  alias BookmarkServer.Accounts
  alias BookmarkServerWeb.UserAuth

  plug :assign_email_and_password_changesets

  def edit(conn, _params) do
    render(conn, :edit)
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"current_password" => password, "user" => user_params} = params
    user = conn.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_update_email_instructions(
          applied_user,
          user.email,
          &Routes.user_settings_url(conn, :confirm_email, &1)
        )

        conn
        |> put_flash(
          :info,
          "A link to confirm your email change has been sent to the new address."
        )
        |> redirect(to: Routes.user_settings_path(conn, :edit))

      {:error, changeset} ->
        render(conn, :edit, email_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "update_password"} = params) do
    %{"current_password" => password, "user" => user_params} = params
    user = conn.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Password updated successfully.")
        |> put_session(:user_return_to, Routes.user_settings_path(conn, :edit))
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, :edit, password_changeset: changeset)
    end
  end

  def update(conn, %{"action" => "empty_account"} = params) do
    %{"current_password" => password, "confirm_email" => confirm_email} = params
    user = conn.assigns.current_user

    cond do
      not BookmarkServer.Accounts.User.valid_password?(user, password) ->
        conn
        |> put_flash(:error, "Wrong password.")
        |> redirect(to: Routes.user_settings_path(conn, :edit))

      String.trim(confirm_email || "") != user.email ->
        conn
        |> put_flash(:error, "Confirmation email didn't match.")
        |> redirect(to: Routes.user_settings_path(conn, :edit))

      true ->
        {:ok, %{sites_deleted: sd, tags_deleted: td}} =
          BookmarkServer.Bookmarks.empty_user_data(user)

        conn
        |> put_flash(:info, "Emptied account: #{sd} bookmarks and #{td} tags deleted.")
        |> redirect(to: Routes.user_settings_path(conn, :edit))
    end
  end

  def update(conn, %{"action" => "deactivate_account"} = params) do
    %{"current_password" => password, "confirm_email" => confirm_email} = params
    user = conn.assigns.current_user

    cond do
      not BookmarkServer.Accounts.User.valid_password?(user, password) ->
        conn
        |> put_flash(:error, "Wrong password.")
        |> redirect(to: Routes.user_settings_path(conn, :edit))

      String.trim(confirm_email || "") != user.email ->
        conn
        |> put_flash(:error, "Confirmation email didn't match.")
        |> redirect(to: Routes.user_settings_path(conn, :edit))

      true ->
        :ok = Accounts.delete_user(user)
        UserAuth.log_out_user(conn)
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_user, token) do
      :ok ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: Routes.user_settings_path(conn, :edit))

      :error ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: Routes.user_settings_path(conn, :edit))
    end
  end

  defp assign_email_and_password_changesets(conn, _opts) do
    user = conn.assigns.current_user

    conn
    |> assign(:email_changeset, Accounts.change_user_email(user))
    |> assign(:password_changeset, Accounts.change_user_password(user))
  end
end
