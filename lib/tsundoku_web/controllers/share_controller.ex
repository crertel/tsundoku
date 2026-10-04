defmodule TsundokuWeb.ShareController do
  use TsundokuWeb, :controller

  alias Tsundoku.Bookmarks

  @doc """
  Endpoint that the OS share sheet POSTs to when the user shares a
  link to the installed PWA. The Android share intent provides
  `title`, `text`, and/or `url` — Android often stuffs the actual
  URL into `text` rather than `url`, so we pull the URL out of
  whichever field has one.
  """
  def receive(conn, params) do
    user = conn.assigns.current_user
    url = pick_url(params)
    title = params["title"] || ""

    cond do
      is_nil(user) ->
        conn
        |> put_session(:user_return_to, "/sites")
        |> put_flash(:error, "Log in to save shared links.")
        |> redirect(to: ~p"/users/log_in")

      is_nil(url) ->
        conn
        |> put_flash(:error, "Couldn't find a URL to save in the shared content.")
        |> redirect(to: ~p"/sites")

      true ->
        case Bookmarks.get_user_bookmark_by_url(url, user.id) do
          %Tsundoku.Bookmarks.Site{} = existing ->
            conn
            |> put_flash(:info, "Already saved: opening for review.")
            |> redirect(to: ~p"/sites/#{existing.id}/edit")

          nil ->
            case Bookmarks.create_site(%{
                   display_name: presence(title) || url,
                   url: url,
                   created_by_id: user.id,
                   tags: []
                 }) do
              {:ok, site} ->
                conn
                |> put_flash(:info, "Saved.")
                |> redirect(to: ~p"/sites/#{site.id}/edit")

              {:error, _changeset} ->
                conn
                |> put_flash(:error, "Couldn't save: invalid URL.")
                |> redirect(to: ~p"/sites")
            end
        end
    end
  end

  defp pick_url(%{"url" => url}) when is_binary(url) and url != "" do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme}} when scheme in ["http", "https"] -> url
      _ -> extract_url_from_text(url)
    end
  end

  defp pick_url(%{"text" => text}) when is_binary(text) and text != "" do
    extract_url_from_text(text)
  end

  defp pick_url(_), do: nil

  defp extract_url_from_text(text) do
    case Regex.run(~r{https?://\S+}, text) do
      [match] -> String.replace(match, ~r/[.,;:!?"']+$/, "")
      _ -> nil
    end
  end

  defp presence(nil), do: nil

  defp presence(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
