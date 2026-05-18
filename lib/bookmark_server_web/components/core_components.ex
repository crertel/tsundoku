defmodule BookmarkServerWeb.CoreComponents do
  @moduledoc """
  Shared HEEx components and helpers used across HTML modules and LiveViews.
  """

  import Phoenix.HTML.Form
  use PhoenixHTMLHelpers

  @doc """
  Generates tag for inlined form input errors.
  """
  def error_tag(form, field) do
    Enum.map(Keyword.get_values(form.errors, field), fn error ->
      content_tag(:span, translate_error(error),
        class: "invalid-feedback",
        phx_feedback_for: input_name(form, field)
      )
    end)
  end

  @doc """
  Translates an error message.
  """
  def translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(inspect(value)))
    end)
  end

  @doc """
  Returns a `data:` URL for a cached favicon, or `nil` if the site
  doesn't have favicon bytes stored. Used inline in the rendered
  HTML so we don't need a public per-favicon endpoint.
  """
  def favicon_data_url(%{favicon_data: data, favicon_content_type: ct})
      when is_binary(data) do
    "data:#{ct || "image/x-icon"};base64,#{Base.encode64(data)}"
  end

  def favicon_data_url(_), do: nil
end
