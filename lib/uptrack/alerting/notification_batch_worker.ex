defmodule Uptrack.Alerting.NotificationBatchWorker do
  @moduledoc """
  Oban cron worker that processes pending (batched) notifications.

  Runs every hour. Collects all undelivered pending notifications,
  groups them by user, and sends a single digest email per user.
  """

  use Oban.Worker,
    queue: :alerts,
    max_attempts: 3

  import Swoosh.Email

  alias Uptrack.AppRepo
  alias Uptrack.Mailer
  alias Uptrack.Alerting.PendingNotification
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    import Ecto.Query, only: [where: 3, order_by: 3]

    pending =
      PendingNotification
      |> where([pn], pn.delivered == false)
      |> order_by([pn], asc: pn.inserted_at)
      |> AppRepo.all()
      |> AppRepo.preload([:incident, :monitor])

    if Enum.empty?(pending) do
      Logger.debug("No pending notifications to batch")
      :ok
    else
      pending
      |> Enum.group_by(& &1.user_id)
      |> Enum.each(fn {_user_id, notifications} ->
        send_digest(notifications)
      end)

      :ok
    end
  end

  defp send_digest(notifications) do
    first = hd(notifications)
    recipient_email = first.recipient_email
    ids = Enum.map(notifications, & &1.id)

    incidents_count = notifications |> Enum.filter(&(&1.event_type == "incident_created")) |> length()
    resolutions_count = notifications |> Enum.filter(&(&1.event_type == "incident_resolved")) |> length()

    subject = build_subject(incidents_count, resolutions_count)

    email =
      new()
      |> to(recipient_email)
      |> from({"Uptrack Monitoring", "alerts@uptrack.dev"})
      |> subject(subject)
      |> html_body(digest_html_body(notifications))
      |> text_body(digest_text_body(notifications))

    case Mailer.deliver(email) do
      {:ok, _} ->
        mark_delivered(ids)
        Logger.info("Sent digest email to #{recipient_email} with #{length(notifications)} notifications")

      {:error, reason} ->
        Logger.error("Failed to send digest to #{recipient_email}: #{inspect(reason)}")
    end
  end

  defp build_subject(incidents, resolutions) do
    parts = []
    parts = if incidents > 0, do: parts ++ ["#{incidents} incident#{if incidents > 1, do: "s", else: ""}"], else: parts
    parts = if resolutions > 0, do: parts ++ ["#{resolutions} resolution#{if resolutions > 1, do: "s", else: ""}"], else: parts
    "Uptrack Digest: #{Enum.join(parts, ", ")}"
  end

  defp mark_delivered(ids) do
    import Ecto.Query, only: [where: 3]

    PendingNotification
    |> where([pn], pn.id in ^ids)
    |> AppRepo.update_all(set: [delivered: true])
  end

  defp digest_html_body(notifications) do
    items =
      notifications
      |> Enum.map(fn n ->
        icon = if n.event_type == "incident_created", do: "🚨", else: "✅"
        action = if n.event_type == "incident_created", do: "went DOWN", else: "is back UP"

        """
        <tr>
          <td style="padding: 12px; border-bottom: 1px solid #e5e5e5;">#{icon}</td>
          <td style="padding: 12px; border-bottom: 1px solid #e5e5e5;">
            <strong>#{n.monitor.name}</strong> #{action}
            <br><span style="color: #666; font-size: 13px;">#{n.monitor.url} • #{Calendar.strftime(n.inserted_at, "%I:%M %p UTC")}</span>
          </td>
        </tr>
        """
      end)
      |> Enum.join()

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Uptrack Notification Digest</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
        .header { background: #3b82f6; color: white; padding: 24px; text-align: center; }
        .header h1 { margin: 0; font-size: 24px; }
        .content { padding: 24px; }
        .footer { background: #f9f9f9; padding: 16px 24px; font-size: 14px; color: #666; text-align: center; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Notification Digest</h1>
        </div>
        <div class="content">
          <p>Here's a summary of recent monitor events:</p>
          <table style="width: 100%; border-collapse: collapse;">
            #{items}
          </table>
          <p style="margin-top: 24px;">
            <a href="#{app_url()}/dashboard" style="display: inline-block; background: #3b82f6; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px;">View Dashboard</a>
          </p>
        </div>
        <div class="footer">
          <p>Uptrack Monitoring • You're receiving this digest based on your notification preferences.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp digest_text_body(notifications) do
    items =
      notifications
      |> Enum.map(fn n ->
        icon = if n.event_type == "incident_created", do: "DOWN", else: "UP"
        "- [#{icon}] #{n.monitor.name} (#{n.monitor.url}) at #{Calendar.strftime(n.inserted_at, "%I:%M %p UTC")}"
      end)
      |> Enum.join("\n")

    """
    Uptrack Notification Digest
    ==========================

    Recent monitor events:

    #{items}

    View dashboard: #{app_url()}/dashboard

    ---
    Uptrack Monitoring
    """
  end

  defp app_url, do: Application.get_env(:uptrack, :app_url, "http://localhost:4000")
end
