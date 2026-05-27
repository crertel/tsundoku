defmodule TsundokuWeb.LiveHelpers do
  alias Tsundoku.Accounts.User
  alias Tsundoku.Accounts

  @doc """
  Renders a component inside the `TsundokuWeb.ModalComponent` component.

  The rendered modal receives a `:return_to` option to properly update
  the URL when the modal is closed.

  ## Examples

      <%= live_modal @socket, TsundokuWeb.TagLive.FormComponent,
        id: @tag.id || :new,
        action: @live_action,
        tag: @tag,
        return_to: Routes.tag_index_path(@socket, :index) %>
  """
  def live_modal(_socket, component, opts) do
    path = Keyword.fetch!(opts, :return_to)

    Phoenix.Component.live_component(%{
      module: TsundokuWeb.ModalComponent,
      id: :modal,
      return_to: path,
      component: component,
      opts: opts
    })
  end

  def assign_defaults(session, socket) do
    socket
    |> Phoenix.Component.assign_new(:current_user, fn ->
      with user_token when not is_nil(user_token) <- session["user_token"],
           %User{} = user <- Accounts.get_user_by_session_token(user_token),
           do: user
    end)
  end

  @doc """
  Asserts that the given record is owned by the user. Returns the record on
  success; raises `Ecto.NoResultsError` on mismatch so that an attempt to
  reach another user's record looks indistinguishable from a missing one.
  """
  def ensure_owner!(%{created_by_id: owner_id} = record, %User{id: owner_id}), do: record

  def ensure_owner!(record, %User{}) do
    raise Ecto.NoResultsError, queryable: record.__struct__
  end
end
