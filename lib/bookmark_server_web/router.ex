defmodule BookmarkServerWeb.Router do
  use BookmarkServerWeb, :router

  import BookmarkServerWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {BookmarkServerWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authed_api do
    plug :accepts, ["json"]
    plug BookmarkServerWeb.Plugs.TokenAccess
  end

  scope "/", BookmarkServerWeb do
    pipe_through :browser

    live "/", PageLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", BookmarkServerWeb do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: BookmarkServerWeb.Telemetry
    end
  end

  ## Authentication routes

  scope "/", BookmarkServerWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
    get "/users/reset_password", UserResetPasswordController, :new
    post "/users/reset_password", UserResetPasswordController, :create
    get "/users/reset_password/:token", UserResetPasswordController, :edit
    put "/users/reset_password/:token", UserResetPasswordController, :update
  end

  scope "/", BookmarkServerWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm_email/:token", UserSettingsController, :confirm_email
  end

  scope "/", BookmarkServerWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete
    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :confirm
  end

  scope "/api", BookmarkServerWeb do
    pipe_through [:api]

    post "/login", UserTokenController, :new
  end

  scope "/api", BookmarkServerWeb do
    pipe_through [:authed_api]

    get "/test", ApiController, :test
    get "/bookmarks/:bookmark_id", ApiController, :get_bookmark
    get "/tags/:tag_id", ApiController, :get_tag
    post "/create_bookmark", ApiController, :create_bookmark
    post "/update_bookmark/:bookmark_id", ApiController, :update_bookmark
    post "/create_tag", ApiController, :create_tag
    post "/update_tag/:tag_id", ApiController, :update_tag
    post "/create_user", ApiController, :create_user
  end

  scope "/", BookmarkServerWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/tags", TagLive.Index, :index
    live "/tags/new", TagLive.Index, :new
    live "/tags/:id/edit", TagLive.Index, :edit
    live "/tags/:id", TagLive.Show, :show
    live "/tags/:id/show/edit", TagLive.Show, :edit

    live "/domains", DomainLive.Index, :index

    live "/sites", SiteLive.Index, :index
    live "/sites/new", SiteLive.Index, :new
    live "/sites/:id/edit", SiteLive.Index, :edit
    live "/sites/:id", SiteLive.Show, :show
    live "/sites/:id/show/edit", SiteLive.Show, :edit
  end
end
