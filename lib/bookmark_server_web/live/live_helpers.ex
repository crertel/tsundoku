defmodule BookmarkServerWeb.LiveHelpers do
  import Phoenix.LiveView.Helpers
  alias BookmarkServer.Accounts.User
  alias BookmarkServer.Accounts

  @doc """
  Renders a component inside the `BookmarkServerWeb.ModalComponent` component.

  The rendered modal receives a `:return_to` option to properly update
  the URL when the modal is closed.

  ## Examples

      <%= live_modal @socket, BookmarkServerWeb.TagLive.FormComponent,
        id: @tag.id || :new,
        action: @live_action,
        tag: @tag,
        return_to: Routes.tag_index_path(@socket, :index) %>
  """
  def live_modal(_socket, component, opts) do
    path = Keyword.fetch!(opts, :return_to)
    modal_opts = [id: :modal, return_to: path, component: component, opts: opts]
    live_component(BookmarkServerWeb.ModalComponent, modal_opts)
  end

  def assign_defaults(session, socket) do
    socket
    |> Phoenix.LiveView.assign_new(:current_user, fn ->
      with user_token when not is_nil(user_token) <- session["user_token"],
      %User{} = user <- Accounts.get_user_by_session_token(user_token),
      do: user
    end)
  end
end
