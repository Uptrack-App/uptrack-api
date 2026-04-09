defmodule UptrackWeb.AckController do
  use UptrackWeb, :controller

  alias Uptrack.Alerting.AckToken
  alias Uptrack.Monitoring

  def acknowledge(conn, %{"token" => token}) do
    case AckToken.verify(token) do
      {:ok, incident_id} ->
        handle_acknowledgment(conn, incident_id)

      {:error, :expired} ->
        html(conn, page("Link Expired", "⚠️", "This acknowledge link has expired (links are valid for 7 days).", nil))

      {:error, _} ->
        html(conn, page("Invalid Link", "⚠️", "This acknowledge link is invalid.", nil))
    end
  end

  defp handle_acknowledgment(conn, incident_id) do
    incident = Monitoring.get_incident!(incident_id)
    monitor = Monitoring.get_monitor!(incident.monitor_id)
    monitor_url = "#{app_url()}/dashboard/monitors/#{monitor.id}"

    if incident.acknowledged_at do
      html(conn, page("Already Acknowledged", "✅", "This incident was already acknowledged.", monitor_url))
    else
      case Monitoring.acknowledge_incident(incident, nil) do
        {:ok, _} ->
          html(conn, page("Incident Acknowledged", "✅", "#{monitor.name} has been acknowledged. Reminders will stop.", monitor_url))

        {:error, _} ->
          html(conn, page("Error", "⚠️", "Could not acknowledge the incident. Please try again from the dashboard.", monitor_url))
      end
    end
  rescue
    Ecto.NoResultsError ->
      html(conn, page("Not Found", "⚠️", "Incident not found.", nil))
  end

  defp page(title, icon, message, dashboard_url) do
    link =
      if dashboard_url do
        ~s(<a href="#{dashboard_url}" style="display:inline-block;margin-top:20px;padding:10px 20px;background:#1a1a2e;color:#fff;text-decoration:none;border-radius:6px;font-size:14px;">Open Dashboard</a>)
      else
        ""
      end

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{title} — Uptrack</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f5f5f5; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
        .card { background: #fff; border-radius: 12px; padding: 40px 48px; text-align: center; max-width: 420px; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
        .icon { font-size: 48px; margin-bottom: 16px; }
        h1 { font-size: 22px; font-weight: 600; margin: 0 0 10px; color: #111; }
        p { color: #555; font-size: 15px; margin: 0; line-height: 1.5; }
      </style>
    </head>
    <body>
      <div class="card">
        <div class="icon">#{icon}</div>
        <h1>#{title}</h1>
        <p>#{message}</p>
        #{link}
      </div>
    </body>
    </html>
    """
  end

  defp app_url, do: Application.get_env(:uptrack, :app_url, "http://localhost:4000")
end
