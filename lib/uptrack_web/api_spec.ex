defmodule UptrackWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Uptrack API.
  """
  alias OpenApiSpex.{Info, OpenApi, Paths, Server, Components, SecurityScheme}
  alias UptrackWeb.Router
  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [
        %Server{url: "https://api.uptrack.app", description: "Production"},
        %Server{url: Application.get_env(:uptrack, :app_url, "http://localhost:4000"), description: "Development"}
      ],
      info: %Info{
        title: "Uptrack API",
        version: "1.0.0",
        description: """
        Uptrack is an uptime monitoring service. This API provides:

        - **Monitor Management** - Create, update, and manage monitors
        - **Heartbeat Endpoints** - Receive heartbeat pings from cron jobs and services
        - **Status Badges** - SVG badges for README files
        - **Status Widgets** - Embeddable status widgets
        - **Subscriptions** - Email notifications for status changes
        - **Team Management** - Manage organization members and invitations
        """
      },
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "session" => %SecurityScheme{
            type: "apiKey",
            in: "cookie",
            name: "_uptrack_key",
            description: "Session-based authentication cookie"
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
