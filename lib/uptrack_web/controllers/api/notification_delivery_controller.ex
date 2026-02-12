defmodule UptrackWeb.Api.NotificationDeliveryController do
  use UptrackWeb, :controller

  alias Uptrack.Alerting.DeliveryTracker

  def index(conn, params) do
    %{current_organization: org} = conn.assigns

    opts =
      []
      |> maybe_add(:limit, params["limit"])
      |> maybe_add(:status, params["status"])
      |> maybe_add(:incident_id, params["incident_id"])

    deliveries = DeliveryTracker.list_deliveries(org.id, opts)

    json(conn, %{
      notification_deliveries:
        Enum.map(deliveries, fn d ->
          %{
            id: d.id,
            channel_type: d.channel_type,
            event_type: d.event_type,
            status: d.status,
            error_message: d.error_message,
            incident_id: d.incident_id,
            monitor_id: d.monitor_id,
            alert_channel_id: d.alert_channel_id,
            inserted_at: d.inserted_at
          }
        end)
    })
  end

  def stats(conn, params) do
    %{current_organization: org} = conn.assigns
    days = parse_days(params["days"])
    stats = DeliveryTracker.get_delivery_stats(org.id, days)

    json(conn, %{stats: stats, period_days: days})
  end

  defp parse_days(nil), do: 7

  defp parse_days(days) when is_binary(days) do
    case Integer.parse(days) do
      {d, _} when d >= 1 and d <= 90 -> d
      _ -> 7
    end
  end

  defp parse_days(days) when is_integer(days) and days >= 1 and days <= 90, do: days
  defp parse_days(_), do: 7

  defp maybe_add(opts, :limit, val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n >= 1 and n <= 200 -> [{:limit, n} | opts]
      _ -> opts
    end
  end

  defp maybe_add(opts, key, val) when is_binary(val) and val != "", do: [{key, val} | opts]
  defp maybe_add(opts, _key, _val), do: opts
end
