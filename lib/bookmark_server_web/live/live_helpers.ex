defmodule BookmarkServerWeb.LiveHelpers do
  import Phoenix.LiveView.Helpers

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
  def live_modal(socket, component, opts) do
    path = Keyword.fetch!(opts, :return_to)
    modal_opts = [id: :modal, return_to: path, component: component, opts: opts]
    live_component(socket, BookmarkServerWeb.ModalComponent, modal_opts)
  end
end
