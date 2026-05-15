defmodule BookmarkServerWeb.Layouts do
  use BookmarkServerWeb, :html

  embed_templates "layouts/*"

  attr :current_user, :any, default: nil

  defp user_menu(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2 text-sm">
      <%= if @current_user do %>
        <div class="max-w-xs truncate rounded-md bg-slate-200 px-3 py-2 font-medium text-slate-800">
          {@current_user.email}
        </div>
        <div>
          <.link
            href={~p"/extension"}
            class="rounded-md px-3 py-2 font-medium text-slate-700 hover:bg-slate-200 hover:text-slate-950"
          >
            Extension
          </.link>
        </div>
        <div>
          <.link
            href={~p"/users/settings"}
            class="rounded-md px-3 py-2 font-medium text-slate-700 hover:bg-slate-200 hover:text-slate-950"
          >
            Settings
          </.link>
        </div>
        <div>
          <.link
            href={~p"/users/log_out"}
            method="delete"
            class="rounded-md px-3 py-2 font-medium text-slate-700 hover:bg-slate-200 hover:text-slate-950"
          >
            Log out
          </.link>
        </div>
      <% else %>
        <div>
          <.link
            href={~p"/users/register"}
            class="rounded-md px-3 py-2 font-medium text-slate-700 hover:bg-slate-200 hover:text-slate-950"
          >
            Register
          </.link>
        </div>
        <div>
          <.link
            href={~p"/users/log_in"}
            class="rounded-md bg-sky-600 px-3 py-2 font-semibold text-white shadow-sm hover:bg-sky-700"
          >
            Log in
          </.link>
        </div>
      <% end %>
    </div>
    """
  end

  defp dashboard_available? do
    function_exported?(BookmarkServerWeb.Router.Helpers, :live_dashboard_path, 2)
  end
end
