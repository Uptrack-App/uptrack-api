defmodule UptrackWeb.Api.HeartbeatController do
  use UptrackWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Uptrack.Monitoring.Heartbeat
  alias UptrackWeb.Schemas.Heartbeat, as: HeartbeatSchemas

  tags ["Heartbeat"]

  operation :ping,
    summary: "Record heartbeat",
    description: "Receives a heartbeat ping from a monitored service. Used for cron job and scheduled task monitoring.",
    parameters: [
      token: [
        in: :path,
        type: :string,
        required: true,
        description: "Unique heartbeat token for the monitor"
      ]
    ],
    request_body: {"Heartbeat payload", "application/json", HeartbeatSchemas.PingRequest, required: false},
    responses: [
      ok: {"Heartbeat recorded", "application/json", HeartbeatSchemas.PingResponse},
      not_found: {"Invalid token", "application/json", HeartbeatSchemas.ErrorResponse}
    ]

  @doc """
  Receives a heartbeat ping from a monitored service.
  POST /api/heartbeat/:token

  Accepts optional JSON body:
  {
    "execution_time": 1234,  // milliseconds
    "status": "success",     // custom status
    "message": "Job completed"
  }
  """
  def ping(conn, %{"token" => token} = params) do
    # Extract optional metadata from body
    metadata = %{
      "execution_time" => params["execution_time"],
      "status" => params["status"],
      "message" => params["message"],
      "received_at" => DateTime.to_iso8601(DateTime.utc_now())
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()

    case Heartbeat.record_heartbeat(token, metadata) do
      {:ok, monitor} ->
        json(conn, %{
          ok: true,
          monitor: %{
            id: monitor.id,
            name: monitor.name,
            status: monitor.status
          }
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{ok: false, error: "Invalid or inactive heartbeat token"})

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{ok: false, error: "Failed to record heartbeat"})
    end
  end

  operation :head_ping,
    summary: "Lightweight heartbeat ping",
    description: "HEAD request for heartbeat - useful for curl-based monitoring scripts.",
    parameters: [
      token: [
        in: :path,
        type: :string,
        required: true,
        description: "Unique heartbeat token for the monitor"
      ]
    ],
    responses: [
      ok: "Heartbeat recorded",
      not_found: "Invalid token"
    ]

  @doc """
  HEAD request for heartbeat (lightweight ping).
  HEAD /api/heartbeat/:token
  """
  def head_ping(conn, %{"token" => token}) do
    case Heartbeat.record_heartbeat(token, %{}) do
      {:ok, _monitor} ->
        send_resp(conn, :ok, "")

      {:error, :not_found} ->
        send_resp(conn, :not_found, "")

      {:error, _} ->
        send_resp(conn, :internal_server_error, "")
    end
  end
end
