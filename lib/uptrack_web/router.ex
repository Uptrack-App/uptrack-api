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
    plug UptrackWeb.Plugs.RateLimit, max_requests: 100, interval_ms: 60_000, bucket: "api"
  end

  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug :fetch_session
    plug UptrackWeb.Plugs.ApiAuth
    plug UptrackWeb.Plugs.RateLimit, max_requests: 200, interval_ms: 60_000, by: :user, bucket: "api_auth"
  end

  # Higher rate limit for heartbeat endpoints (services may ping frequently)
  pipeline :api_heartbeat do
    plug :accepts, ["json"]
    plug UptrackWeb.Plugs.RateLimit, max_requests: 1000, interval_ms: 60_000, by: :token, bucket: "heartbeat"
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

  # Health check endpoints (for load balancers and systemd)
  scope "/", UptrackWeb do
    pipe_through :health

    # Liveness probe - is the app running?
    get "/healthz", HealthController, :show

    # Readiness probe - is the app ready to serve traffic?
    get "/ready", HealthController, :ready

    # Convenience alias used by systemd postStart and external monitors
    get "/api/health", HealthController, :ready
  end

  # API auth routes (no authentication required)
  scope "/api/auth", UptrackWeb.Api do
    pipe_through [:api, :fetch_session]

    get "/providers", AuthController, :providers
    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/verify-2fa", AuthController, :verify_2fa
  end

  # API routes for TanStack Start frontend
  scope "/api", UptrackWeb.Api do
    pipe_through :api_authenticated

    # Auth management (authenticated)
    get "/auth/me", AuthController, :me
    post "/auth/logout", AuthController, :logout
    patch "/auth/profile", AuthController, :update_profile
    patch "/auth/password", AuthController, :change_password
    delete "/auth/account", AuthController, :delete_account

    # Two-factor authentication
    get "/auth/2fa/status", TwoFactorController, :status
    post "/auth/2fa/setup", TwoFactorController, :setup
    post "/auth/2fa/confirm", TwoFactorController, :confirm
    post "/auth/2fa/disable", TwoFactorController, :disable

    # Custom email sender
    get "/custom-sender", CustomSenderController, :show
    post "/custom-sender", CustomSenderController, :create
    delete "/custom-sender", CustomSenderController, :delete

    # Team management
    scope "/organizations/:organization_id" do
      resources "/members", TeamController, only: [:index, :update, :delete]
      post "/members/transfer-ownership", TeamController, :transfer_ownership

      resources "/invitations", InvitationController, only: [:index, :create, :delete]

      resources "/audit-logs", AuditLogController, only: [:index]
    end

    # API key management
    resources "/api-keys", ApiKeyController, only: [:index, :create, :delete]
    post "/api-keys/:id/revoke", ApiKeyController, :revoke

    # Monitor API
    post "/monitors/smart-defaults", MonitorController, :smart_defaults
    resources "/monitors", MonitorController, only: [:index, :create, :show, :update, :delete]
    get "/monitors/:monitor_id/checks", MonitorController, :checks

    # Alert channel API
    resources "/alert-channels", AlertChannelController, only: [:index, :create, :show, :update, :delete]
    get "/alert-channels/allowed-types", AlertChannelController, :allowed_types
    post "/alert-channels/:id/test", AlertChannelController, :test

    # Incident API
    resources "/incidents", IncidentController, only: [:index, :show, :create, :update] do
      post "/updates", IncidentController, :create_update
      post "/acknowledge", IncidentController, :acknowledge
    end

    # Escalation policies API
    resources "/escalation-policies", EscalationPolicyController, only: [:index, :create, :show, :update, :delete]

    # Maintenance windows API
    resources "/maintenance-windows", MaintenanceWindowController, only: [:index, :create, :show, :update, :delete]

    # Status page API
    resources "/status-pages", StatusPageController, only: [:index, :create, :show, :update, :delete]

    # Dashboard stats API
    get "/dashboard/stats", DashboardController, :stats

    # Analytics API
    get "/analytics/dashboard", AnalyticsController, :dashboard
    get "/analytics/monitors/:monitor_id", AnalyticsController, :monitor_stats
    get "/analytics/organization/trends", AnalyticsController, :organization_trends
    get "/analytics/export", ExportController, :export

    # Notification delivery history
    get "/notification-deliveries", NotificationDeliveryController, :index
    get "/notification-deliveries/stats", NotificationDeliveryController, :stats

    # Custom domain management
    get "/status-pages/:status_page_id/domain", DomainController, :show
    put "/status-pages/:status_page_id/domain", DomainController, :update
    post "/status-pages/:status_page_id/domain/verify", DomainController, :verify
    delete "/status-pages/:status_page_id/domain", DomainController, :delete

    # Integration OAuth initiation (requires auth)
    get "/integrations/slack/auth", IntegrationController, :slack_auth
    get "/integrations/discord/auth", IntegrationController, :discord_auth

    # Billing
    post "/billing/checkout", BillingController, :checkout
    get "/billing/subscription", BillingController, :subscription
    post "/billing/cancel", BillingController, :cancel
    post "/billing/change-plan", BillingController, :change_plan
    post "/billing/portal", BillingController, :portal
    get "/billing/downgrade-preview", BillingController, :downgrade_preview
  end

  # OAuth callbacks (no auth - redirects from OAuth providers)
  scope "/api/integrations", UptrackWeb.Api do
    pipe_through :api

    get "/slack/callback", IntegrationController, :slack_callback
    get "/discord/callback", IntegrationController, :discord_callback
  end

  # Heartbeat endpoints (higher rate limit for services)
  scope "/api", UptrackWeb.Api do
    pipe_through :api_heartbeat

    post "/heartbeat/:token", HeartbeatController, :ping
    head "/heartbeat/:token", HeartbeatController, :head_ping
  end

  # Webhook routes (no auth — signature verified in controller)
  # Uses CacheBodyReader to preserve raw body for HMAC verification
  scope "/api/webhooks", UptrackWeb.Api do
    pipe_through :api

    post "/paddle", WebhookController, :paddle
  end

  # Public API routes (no authentication required)
  scope "/api", UptrackWeb.Api do
    pipe_through :api

    # OpenAPI specification
    get "/openapi", OpenApiController, :spec

    # Invitation acceptance (token-based, may or may not be authenticated)
    get "/invitations/:token", InvitationController, :show_by_token
    post "/invitations/:token/accept", InvitationController, :accept

    # Custom sender email verification (public, no auth)
    get "/custom-sender/verify/:token", CustomSenderController, :verify

    # Public status page API (no auth required)
    get "/status/:slug", StatusPageController, :show_public
    get "/status/:slug/uptime", StatusPageController, :public_uptime

    # Status page badges (public, no auth required)
    get "/badge/:slug", StatusBadgeController, :show
    get "/badge/:slug/status", StatusBadgeController, :status
    get "/badge/:slug/uptime", StatusBadgeController, :uptime

    # Status page embeddable widgets
    get "/widget/:slug/script.js", StatusWidgetController, :script
    get "/widget/:slug/data", StatusWidgetController, :data

    # Status page subscriptions
    post "/status/:slug/subscribe", SubscriberController, :subscribe
    get "/subscribe/verify/:token", SubscriberController, :verify
    get "/subscribe/unsubscribe/:token", SubscriberController, :unsubscribe
  end

  # Enable LiveDashboard, Swoosh mailbox preview, and SwaggerUI in development
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

    # Swagger UI for API documentation
    scope "/api" do
      pipe_through :browser

      get "/docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
    end
  end
end
