defmodule BookmarkServerWeb.PageLive do
  use BookmarkServerWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    socket = assign_defaults(session, socket)

    case socket.assigns[:current_user] do
      %BookmarkServer.Accounts.User{} ->
        {:ok, redirect(socket, to: ~p"/sites")}

      _ ->
        {:ok, assign(socket, page_title: "Tsundoku")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-2xl px-4 py-16 sm:px-6 lg:px-8">
      <div class="rounded-lg border border-slate-400 bg-slate-100 p-8 shadow-sm">
        <h1 class="text-3xl font-semibold text-slate-950">Tsundoku</h1>
        <p class="mt-3 text-sm text-slate-700">
          A personal bookmarks server. Log in or register to begin.
        </p>

        <div class="mt-6 flex gap-3">
          <.link
            href={~p"/users/log_in"}
            class="rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700"
          >
            Log in
          </.link>
          <.link
            href={~p"/users/register"}
            class="rounded-md border border-slate-400 bg-slate-50 px-4 py-2 text-sm font-semibold text-slate-700 shadow-sm hover:bg-slate-200"
          >
            Register
          </.link>
        </div>
      </div>
    </section>
    """
  end
end
