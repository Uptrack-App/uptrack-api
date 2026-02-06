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

  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug :fetch_session
    plug UptrackWeb.Plugs.ApiAuth
  end

  pipeline :health do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug :browser
    plug Ueberauth
  end

  # Public routes (no authentication required)
  scope "/", UptrackWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/auth/signup", AuthLive.Signup, :new

    # Session management
    post "/auth/register", SessionController, :create
    post "/auth/login", SessionController, :login

    # Public status page routes
    live "/status/:slug", StatusLive, :show

    # Status widget routes
    live "/widget/:slug", StatusWidgetLive, :show
  end

  # Protected routes (authentication required)
  scope "/", UptrackWeb do
    pipe_through :browser

    live_session :authenticated,
      on_mount: [{UptrackWeb.UserAuth, :require_authenticated_user}] do
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
    end
  end

  scope "/auth", UptrackWeb do
    pipe_through :auth

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :logout
  end

  # Health check endpoint (for load balancers)
  scope "/", UptrackWeb do
    pipe_through :health

    get "/healthz", HealthController, :show
  end

  # API routes for TanStack Start frontend
  scope "/api", UptrackWeb.Api do
    pipe_through :api_authenticated

    # Team management
    scope "/organizations/:organization_id" do
      resources "/members", TeamController, only: [:index, :update, :delete]
      post "/members/transfer-ownership", TeamController, :transfer_ownership

      resources "/invitations", InvitationController, only: [:index, :create, :delete]

      resources "/audit-logs", AuditLogController, only: [:index]
    end

    # Monitor API
    post "/monitors/smart-defaults", MonitorController, :smart_defaults
    resources "/monitors", MonitorController, only: [:index, :create, :show, :update, :delete]

    # Integration OAuth initiation (requires auth)
    get "/integrations/slack/auth", IntegrationController, :slack_auth
    get "/integrations/discord/auth", IntegrationController, :discord_auth
  end

  # OAuth callbacks (no auth - redirects from OAuth providers)
  scope "/api/integrations", UptrackWeb.Api do
    pipe_through :api

    get "/slack/callback", IntegrationController, :slack_callback
    get "/discord/callback", IntegrationController, :discord_callback
  end

  # Public API routes (no authentication required)
  scope "/api", UptrackWeb.Api do
    pipe_through :api

    # Invitation acceptance (token-based, may or may not be authenticated)
    get "/invitations/:token", InvitationController, :show_by_token
    post "/invitations/:token/accept", InvitationController, :accept

    # Heartbeat receiver (passive monitoring)
    post "/heartbeat/:token", HeartbeatController, :ping
    head "/heartbeat/:token", HeartbeatController, :head_ping

    # Status page badges (public, no auth required)
    get "/badge/:slug", StatusBadgeController, :show
    get "/badge/:slug/status", StatusBadgeController, :status
    get "/badge/:slug/uptime", StatusBadgeController, :uptime

    # Status page embeddable widgets
    get "/widget/:slug/script.js", StatusWidgetController, :script
    get "/widget/:slug/data", StatusWidgetController, :data
  end

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
