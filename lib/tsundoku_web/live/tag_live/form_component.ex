defmodule TsundokuWeb.TagLive.FormComponent do
  use TsundokuWeb, :live_component

  alias Tsundoku.Bookmarks

  @impl true
  def update(%{tag: tag} = assigns, socket) do
    changeset = Bookmarks.change_tag(tag)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"tag" => tag_params}, socket) do
    changeset =
      socket.assigns.tag
      |> Bookmarks.change_tag(tag_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"tag" => tag_params}, socket) do
    save_tag(
      socket,
      socket.assigns.action,
      tag_params |> Map.put("created_by", socket.assigns.current_user)
    )
  end

  defp save_tag(socket, :edit, tag_params) do
    # TODO: only let us update our own tags
    case Bookmarks.update_tag(socket.assigns.tag, tag_params) do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag updated successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_tag(socket, :new, tag_params) do
    params = tag_params |> Map.put("created_by_id", socket.assigns.current_user.id)

    case Bookmarks.create_tag(params) do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag created successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pr-8">
    <div class="border-b border-slate-300 pb-4">
      <h2 class="text-xl font-semibold text-slate-950"><%= @title %></h2>
    </div>

    <.form :let={f}
    for={@changeset}
    id="tag-form"
    phx-target={@myself}
    phx-change="validate"
    phx-submit="save"
    class="mt-6 space-y-5">

    <div>
      <%= label f, :name, class: "block text-sm font-medium text-slate-700" %>
      <%= text_input f, :name, class: "mt-2 block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200" %>
      <%= error_tag f, :name %>
    </div>

    <div>
      <%= label f, :description, class: "block text-sm font-medium text-slate-700" %>
      <%= textarea f, :description, rows: 3, class: "mt-2 block w-full rounded-md border border-slate-400 bg-slate-50 px-3 py-2 text-slate-950 shadow-sm focus:border-sky-500 focus:outline-none focus:ring-2 focus:ring-sky-200" %>
      <%= error_tag f, :description %>
    </div>

    <div class="flex justify-end border-t border-slate-300 pt-5">
      <%= submit "Save", phx_disable_with: "Saving...", class: "rounded-md bg-sky-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-sky-700" %>
    </div>
    </.form>

    </div>
    """
  end
end
