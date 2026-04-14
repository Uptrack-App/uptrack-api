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

  @doc """
  Lists notification deliveries across all organizations with optional filters.
  Joins organization and alert_channel for display names.
  """
  def list_platform_deliveries(opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    per_page = min(Keyword.get(opts, :per_page, 50), 100)
    offset = (page - 1) * per_page
    channel_type = Keyword.get(opts, :channel_type)
    status = Keyword.get(opts, :status)

    base =
      from d in NotificationDelivery,
        join: o in assoc(d, :organization),
        left_join: ac in assoc(d, :alert_channel),
        order_by: [desc: d.inserted_at],
        select: %{
          id: d.id,
          channel_type: d.channel_type,
          event_type: d.event_type,
          status: d.status,
          error_message: d.error_message,
          organization_name: o.name,
          channel_name: ac.name,
          inserted_at: d.inserted_at
        }

    filtered =
      base
      |> maybe_filter_status(status)
      |> maybe_filter_channel_type(channel_type)

    total = AppRepo.aggregate(filtered, :count)

    data =
      filtered
      |> limit(^per_page)
      |> offset(^offset)
      |> AppRepo.all()

    %{data: data, page: page, per_page: per_page, total: total}
  end

  @doc """
  Groups failed deliveries by channel_type and error_message over last N days.
  Returns top 20 error groups.
  """
  def get_error_breakdown(days \\ 7) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86400, :second)

    from(d in NotificationDelivery,
      where: d.status == "failed" and d.inserted_at >= ^cutoff,
      group_by: [d.channel_type, d.error_message],
      select: %{channel_type: d.channel_type, error_message: d.error_message, count: count(d.id)},
      order_by: [desc: count(d.id)],
      limit: 20
    )
    |> AppRepo.all()
  end

  @doc """
  Returns the last successful delivery timestamp per channel_type.
  """
  def get_last_success_per_channel_type(days \\ 7) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86400, :second)

    from(d in NotificationDelivery,
      where: d.status == "delivered" and d.inserted_at >= ^cutoff,
      group_by: d.channel_type,
      select: {d.channel_type, max(d.inserted_at)}
    )
    |> AppRepo.all()
    |> Map.new()
  end

  defp maybe_filter_channel_type(query, nil), do: query
  defp maybe_filter_channel_type(query, ct), do: where(query, [d], d.channel_type == ^ct)

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status) do
    where(query, [d], d.status == ^status)
  end

  defp maybe_filter_incident(query, nil), do: query

  defp maybe_filter_incident(query, incident_id) do
    where(query, [d], d.incident_id == ^incident_id)
  end
end
