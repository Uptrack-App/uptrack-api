defmodule UptrackWeb.Router do
  use UptrackWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {UptrackWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug :browser
    plug Ueberauth
  end

  scope "/", UptrackWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/auth/signup", AuthLive.Signup, :new

    # Dashboard routes
    live "/dashboard", DashboardLive, :index
    live "/dashboard/monitors/new", DashboardLive, :new_monitor

    # Monitor routes
    live "/dashboard/monitors/:id", MonitorLive.Show, :show
    live "/dashboard/monitors/:id/edit", MonitorLive.Show, :edit

    # Alert channel routes
    live "/dashboard/alerts", AlertChannelLive, :index
    live "/dashboard/alerts/new", AlertChannelLive, :new
    live "/dashboard/alerts/:id/edit", AlertChannelLive, :edit

    # Status page management routes
    live "/dashboard/status-pages", StatusPageLive, :index
    live "/dashboard/status-pages/new", StatusPageLive, :new
    live "/dashboard/status-pages/:id/edit", StatusPageLive, :edit
    live "/dashboard/status-pages/:id/widgets", StatusPageLive, :widgets

    # Incident management routes
    live "/dashboard/incidents", IncidentLive, :index
    live "/dashboard/incidents/:id", IncidentLive, :show

    # Settings routes
    live "/dashboard/settings", SettingsLive, :index

    # Public status page routes
    live "/status/:slug", StatusLive, :show
    
    # Status widget routes
    live "/widget/:slug", StatusWidgetLive, :show
  end

  scope "/auth", UptrackWeb do
    pipe_through :auth

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :logout
  end

  # Other scopes may use custom stacks.
  # scope "/api", UptrackWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:uptrack, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: UptrackWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
