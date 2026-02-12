defmodule UptrackWeb.Schemas.Monitor do
  @moduledoc """
  OpenAPI schemas for monitor endpoints.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  defmodule Monitor do
    OpenApiSpex.schema(%{
      title: "Monitor",
      description: "A monitor configuration",
      type: :object,
      required: [:id, :name, :monitor_type, :status],
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, example: "API Health Check"},
        monitor_type: %Schema{
          type: :string,
          enum: ["http", "heartbeat", "tcp", "dns"],
          example: "http"
        },
        status: %Schema{
          type: :string,
          enum: ["active", "paused"],
          example: "active"
        },
        url: %Schema{type: :string, format: :uri, example: "https://api.example.com/health"},
        method: %Schema{type: :string, enum: ["GET", "POST", "HEAD"], example: "GET"},
        interval_seconds: %Schema{type: :integer, example: 60},
        timeout_seconds: %Schema{type: :integer, example: 30},
        settings: %Schema{
          type: :object,
          description: "Monitor-type specific settings"
        },
        organization_id: %Schema{type: :string, format: :uuid},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      }
    })
  end

  defmodule CreateRequest do
    OpenApiSpex.schema(%{
      title: "MonitorCreateRequest",
      description: "Request to create a new monitor",
      type: :object,
      required: [:name, :monitor_type],
      properties: %{
        name: %Schema{type: :string, example: "Production API"},
        monitor_type: %Schema{
          type: :string,
          enum: ["http", "heartbeat", "tcp", "dns"],
          example: "http"
        },
        url: %Schema{type: :string, format: :uri, example: "https://api.example.com/health"},
        method: %Schema{type: :string, enum: ["GET", "POST", "HEAD"], default: "GET"},
        interval_seconds: %Schema{type: :integer, default: 60, minimum: 30, maximum: 86400},
        timeout_seconds: %Schema{type: :integer, default: 30, minimum: 5, maximum: 120},
        settings: %Schema{type: :object}
      }
    })
  end

  defmodule UpdateRequest do
    OpenApiSpex.schema(%{
      title: "MonitorUpdateRequest",
      description: "Request to update a monitor",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        url: %Schema{type: :string, format: :uri},
        method: %Schema{type: :string, enum: ["GET", "POST", "HEAD"]},
        interval_seconds: %Schema{type: :integer, minimum: 30, maximum: 86400},
        timeout_seconds: %Schema{type: :integer, minimum: 5, maximum: 120},
        status: %Schema{type: :string, enum: ["active", "paused"]},
        settings: %Schema{type: :object}
      }
    })
  end

  defmodule SmartDefaultsRequest do
    OpenApiSpex.schema(%{
      title: "SmartDefaultsRequest",
      description: "Request to get smart defaults for a URL",
      type: :object,
      required: [:url],
      properties: %{
        url: %Schema{type: :string, format: :uri, example: "https://api.example.com"}
      }
    })
  end

  defmodule SmartDefaultsResponse do
    OpenApiSpex.schema(%{
      title: "SmartDefaultsResponse",
      description: "Smart defaults based on URL analysis",
      type: :object,
      properties: %{
        name: %Schema{type: :string, example: "api.example.com"},
        url: %Schema{type: :string, format: :uri},
        method: %Schema{type: :string, enum: ["GET", "HEAD"]},
        expected_status_code: %Schema{type: :integer, example: 200},
        interval_seconds: %Schema{type: :integer, example: 60}
      }
    })
  end

  defmodule ListResponse do
    OpenApiSpex.schema(%{
      title: "MonitorListResponse",
      description: "List of monitors",
      type: :object,
      properties: %{
        data: %Schema{
          type: :array,
          items: UptrackWeb.Schemas.Monitor.Monitor
        }
      }
    })
  end
end
