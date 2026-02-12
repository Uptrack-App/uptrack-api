defmodule Uptrack.Alerting.DeliveryTracker do
  @moduledoc """
  Tracks notification delivery attempts and their outcomes.
  """

  import Ecto.Query, warn: false
  alias Uptrack.AppRepo
  alias Uptrack.Alerting.NotificationDelivery

  def record_delivery(attrs) do
    %NotificationDelivery{}
    |> NotificationDelivery.changeset(attrs)
    |> AppRepo.insert()
  end

  def record_success(attrs) do
    record_delivery(Map.put(attrs, :status, "delivered"))
  end

  def record_failure(attrs, error_message) do
    attrs
    |> Map.put(:status, "failed")
    |> Map.put(:error_message, to_string(error_message))
    |> record_delivery()
  end

  def record_skipped(attrs, reason) do
    attrs
    |> Map.put(:status, "skipped")
    |> Map.put(:error_message, to_string(reason))
    |> record_delivery()
  end

  def list_deliveries(organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status)
    incident_id = Keyword.get(opts, :incident_id)

    NotificationDelivery
    |> where([d], d.organization_id == ^organization_id)
    |> maybe_filter_status(status)
    |> maybe_filter_incident(incident_id)
    |> order_by([d], desc: d.inserted_at)
    |> limit(^limit)
    |> AppRepo.all()
  end

  def get_delivery_stats(organization_id, days \\ 7) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    query =
      from d in NotificationDelivery,
        where: d.organization_id == ^organization_id and d.inserted_at >= ^cutoff,
        group_by: d.status,
        select: {d.status, count(d.id)}

    AppRepo.all(query) |> Map.new()
  end

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    where(query, [d], d.status == ^status)
  end

  defp maybe_filter_incident(query, nil), do: query

  defp maybe_filter_incident(query, incident_id) do
    where(query, [d], d.incident_id == ^incident_id)
  end
end
