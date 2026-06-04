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

  # ---- Bookmarks PubSub: debounced refetch on context-level mutations ----
  #
  # Every Bookmarks.{create,update,delete}_{site,tag} broadcasts an
  # ID-only event on `Tsundoku.Bookmarks.topic(user_id)`. LiveViews
  # opt in via `subscribe_to_bookmarks/2` at mount and define two
  # handle_info clauses:
  #
  #   def handle_info({:bookmarks_event, _kind, _payload}, socket),
  #     do: {:noreply, schedule_bookmarks_refetch(socket)}
  #
  #   def handle_info(:bookmarks_refetch, socket),
  #     do: {:noreply, reload_my_data(socket)}
  #
  # The debouncer collapses a burst of mutations (e.g., bulk import,
  # rapid tag toggling) into one refetch ~500ms after the last event.
  #
  # Filter-aware refetch (only re-querying when the changed record
  # intersects the current filter set) is future work — for now this
  # is filter-blind: any event triggers a re-query of the current
  # view. Single-user DB, queries are cheap, debouncer caps cost.

  @bookmarks_debounce_ms 500

  @doc """
  Subscribes the calling LiveView process to the user's bookmarks
  topic on the connected mount. No-op during the dead-render mount.
  """
  def subscribe_to_bookmarks(socket, user_id) do
    if Phoenix.LiveView.connected?(socket) and is_binary(user_id) do
      Tsundoku.Bookmarks.subscribe(user_id)
    end

    socket
  end

  @doc """
  Cancels any pending refetch timer and schedules a fresh
  `:bookmarks_refetch` message after `@bookmarks_debounce_ms`.
  """
  def schedule_bookmarks_refetch(socket) do
    if timer = socket.assigns[:bookmarks_refetch_timer] do
      Process.cancel_timer(timer)
    end

    timer = Process.send_after(self(), :bookmarks_refetch, @bookmarks_debounce_ms)
    Phoenix.Component.assign(socket, :bookmarks_refetch_timer, timer)
  end
end
