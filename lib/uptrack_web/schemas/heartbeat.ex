defmodule UptrackWeb.Schemas.Heartbeat do
  @moduledoc """
  OpenAPI schemas for heartbeat endpoints.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  defmodule PingRequest do
    OpenApiSpex.schema(%{
      title: "HeartbeatPingRequest",
      description: "Optional payload for heartbeat ping",
      type: :object,
      properties: %{
        execution_time: %Schema{
          type: :integer,
          description: "Execution time in milliseconds",
          example: 1234
        },
        status: %Schema{
          type: :string,
          description: "Custom status message",
          example: "success"
        },
        message: %Schema{
          type: :string,
          description: "Optional message or details",
          example: "Job completed successfully"
        }
      }
    })
  end

  defmodule PingResponse do
    OpenApiSpex.schema(%{
      title: "HeartbeatPingResponse",
      description: "Response from heartbeat ping",
      type: :object,
      required: [:ok],
      properties: %{
        ok: %Schema{type: :boolean, example: true},
        monitor: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :string, format: :uuid},
            name: %Schema{type: :string, example: "Daily backup job"},
            status: %Schema{type: :string, enum: ["active", "paused"]}
          }
        }
      }
    })
  end

  defmodule ErrorResponse do
    OpenApiSpex.schema(%{
      title: "HeartbeatErrorResponse",
      description: "Error response from heartbeat endpoint",
      type: :object,
      required: [:ok, :error],
      properties: %{
        ok: %Schema{type: :boolean, example: false},
        error: %Schema{type: :string, example: "Invalid or inactive heartbeat token"}
      }
    })
  end
end
