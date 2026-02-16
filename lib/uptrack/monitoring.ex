defmodule Uptrack.Monitoring do
  @moduledoc """
  The Monitoring context.
  """

  import Ecto.Query, warn: false
  alias Uptrack.AppRepo

  alias Uptrack.Monitoring.{
    Monitor,
    MonitorCheck,
    Incident,
    IncidentUpdate,
    AlertChannel,
    StatusPage,
    StatusPageMonitor,
    StatusPageSubscriber
  }

  # Resource count functions (used by plan enforcement)

  def count_monitors(organization_id) do
    from(m in Monitor, where: m.organization_id == ^organization_id)
    |> AppRepo.aggregate(:count)
  end

  def count_alert_channels(organization_id) do
    from(a in AlertChannel, where: a.organization_id == ^organization_id)
    |> AppRepo.aggregate(:count)
  end

  def count_status_pages(organization_id) do
    from(s in StatusPage, where: s.organization_id == ^organization_id)
    |> AppRepo.aggregate(:count)
  end

  # Monitor functions

  @doc """
  Returns the list of monitors for an organization.
  """
  def list_monitors(organization_id) do
    latest_check_query =
      from(c in MonitorCheck,
        distinct: c.monitor_id,
        order_by: [desc: c.checked_at]
      )

    Monitor
    |> where([m], m.organization_id == ^organization_id)
    |> order_by([m], desc: m.inserted_at)
    |> preload(monitor_checks: ^latest_check_query)
    |> AppRepo.all()
  end

  @doc """
  Returns the list of active monitors for an organization.
  """
  def list_active_monitors(organization_id) do
    Monitor
    |> where([m], m.organization_id == ^organization_id and m.status == "active")
    |> AppRepo.all()
  end

  @doc """
  Returns all active monitors across all users (for scheduler).
  """
  def get_all_active_monitors do
    Monitor
    |> where([m], m.status == "active")
    |> AppRepo.all()
  end

  @doc """
  Gets a single monitor.
  """
  def get_monitor!(id), do: AppRepo.get!(Monitor, id)

  @doc """
  Gets a monitor by organization. Raises if not found.
  """
  def get_organization_monitor!(organization_id, monitor_id) do
    Monitor
    |> where([m], m.organization_id == ^organization_id and m.id == ^monitor_id)
    |> AppRepo.one!()
  end

  @doc """
  Gets a monitor by organization. Returns nil if not found.
  """
  def get_organization_monitor(organization_id, monitor_id) do
    latest_check_query = from(mc in MonitorCheck, order_by: [desc: mc.checked_at], limit: 1)

    Monitor
    |> where([m], m.organization_id == ^organization_id and m.id == ^monitor_id)
    |> preload(monitor_checks: ^latest_check_query)
    |> AppRepo.one()
  end

  @doc """
  Creates a monitor.
  """
  def create_monitor(attrs) do
    result =
      %Monitor{}
      |> Monitor.create_changeset(attrs)
      |> AppRepo.insert()

    with {:ok, monitor} <- result do
      invalidate_org_cache(monitor.organization_id)
      {:ok, monitor}
    end
  end

  @doc """
  Updates a monitor.
  """
  def update_monitor(%Monitor{} = monitor, attrs) do
    result =
      monitor
      |> Monitor.changeset(attrs)
      |> AppRepo.update()

    with {:ok, updated} <- result do
      invalidate_org_cache(updated.organization_id)
      invalidate_monitor_cache(updated.id)
      {:ok, updated}
    end
  end

  @doc """
  Deletes a monitor.
  """
  def delete_monitor(%Monitor{} = monitor) do
    result = AppRepo.delete(monitor)

    with {:ok, deleted} <- result do
      invalidate_org_cache(deleted.organization_id)
      invalidate_monitor_cache(deleted.id)
      {:ok, deleted}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking monitor changes.
  """
  def change_monitor(%Monitor{} = monitor, attrs \\ %{}) do
    Monitor.changeset(monitor, attrs)
  end

  # Monitor Check functions

  @doc """
  Creates a monitor check.
  """
  def create_monitor_check(attrs) do
    MonitorCheck.create_changeset(attrs)
    |> AppRepo.insert()
  end

  @doc """
  Creates a monitor check (alias for create_monitor_check).
  """
  def create_check(attrs), do: create_monitor_check(attrs)

  @doc """
  Returns recent checks for a monitor.
  """
  def get_recent_checks(monitor_id, limit \\ 50) do
    MonitorCheck
    |> where([mc], mc.monitor_id == ^monitor_id)
    |> order_by([mc], desc: mc.checked_at)
    |> limit(^limit)
    |> AppRepo.all()
  end

  @doc """
  Returns the latest check for a monitor.
  """
  def get_latest_check(monitor_id) do
    MonitorCheck
    |> where([mc], mc.monitor_id == ^monitor_id)
    |> order_by([mc], desc: mc.checked_at)
    |> limit(1)
    |> AppRepo.one()
  end

  @doc """
  Returns uptime percentage for a monitor over the last N days.
  """
  def get_uptime_percentage(monitor_id, days \\ 30) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    query =
      from mc in MonitorCheck,
        where: mc.monitor_id == ^monitor_id and mc.checked_at >= ^cutoff_date,
        select: %{
          total: count(mc.id),
          up: count(mc.id) |> filter(mc.status == "up")
        }

    case AppRepo.one(query) do
      %{total: 0} -> 100.0
      %{total: total, up: up} -> (up / total * 100) |> Float.round(2)
    end
  end

  # Alert confirmation functions

  @doc """
  Atomically increments the consecutive failure counter for a monitor.
  Returns {count_updated, nil}.
  """
  def increment_consecutive_failures(monitor_id) do
    from(m in Monitor, where: m.id == ^monitor_id)
    |> AppRepo.update_all(inc: [consecutive_failures: 1])
  end

  @doc """
  Resets the consecutive failure counter to 0.
  Only updates if counter is already > 0 (avoids unnecessary writes).
  """
  def reset_consecutive_failures(monitor_id) do
    from(m in Monitor, where: m.id == ^monitor_id and m.consecutive_failures > 0)
    |> AppRepo.update_all(set: [consecutive_failures: 0])
  end

  @doc """
  Returns the current consecutive failure count for a monitor.
  """
  def get_consecutive_failures(monitor_id) do
    from(m in Monitor, where: m.id == ^monitor_id, select: m.consecutive_failures)
    |> AppRepo.one()
  end

  # Incident functions

  @doc """
  Creates an incident.
  """
  def create_incident(attrs) do
    result =
      Incident.create_changeset(attrs)
      |> AppRepo.insert()

    with {:ok, incident} <- result do
      invalidate_org_cache(incident.organization_id)
      invalidate_monitor_cache(incident.monitor_id)
      {:ok, incident}
    end
  end

  @doc """
  Resolves an incident.
  """
  def resolve_incident(%Incident{} = incident, attrs \\ %{}) do
    result =
      incident
      |> Incident.resolve_changeset(attrs)
      |> AppRepo.update()

    with {:ok, resolved} <- result do
      invalidate_org_cache(resolved.organization_id)
      invalidate_monitor_cache(resolved.monitor_id)
      {:ok, resolved}
    end
  end

  @doc """
  Returns ongoing incidents for a monitor.
  """
  def get_ongoing_incident(monitor_id) do
    Incident
    |> where([i], i.monitor_id == ^monitor_id and i.status == "ongoing")
    |> AppRepo.one()
  end

  @doc """
  Returns any active (non-resolved) incident for a monitor.
  Active means ongoing, investigating, or identified.
  """
  def get_active_incident(monitor_id) do
    Incident
    |> where([i], i.monitor_id == ^monitor_id)
    |> where([i], i.status in ["ongoing", "investigating", "identified"])
    |> AppRepo.one()
  end

  @doc """
  Returns recent incidents for an organization.
  """
  def list_recent_incidents(organization_id, limit \\ 20) do
    query =
      from i in Incident,
        where: i.organization_id == ^organization_id,
        order_by: [desc: i.started_at],
        limit: ^limit,
        preload: [:monitor]

    AppRepo.all(query)
  end

  # Alert Channel functions

  @doc """
  Returns the list of alert channels for an organization.
  """
  def list_alert_channels(organization_id) do
    AlertChannel
    |> where([ac], ac.organization_id == ^organization_id)
    |> order_by([ac], asc: ac.name)
    |> AppRepo.all()
  end

  @doc """
  Gets a single alert channel.
  """
  def get_alert_channel!(id), do: AppRepo.get!(AlertChannel, id)

  @doc """
  Creates an alert channel.
  """
  def create_alert_channel(attrs) do
    %AlertChannel{}
    |> AlertChannel.changeset(attrs)
    |> AppRepo.insert()
  end

  @doc """
  Updates an alert channel.
  """
  def update_alert_channel(%AlertChannel{} = alert_channel, attrs) do
    alert_channel
    |> AlertChannel.changeset(attrs)
    |> AppRepo.update()
  end

  @doc """
  Deletes an alert channel.
  """
  def delete_alert_channel(%AlertChannel{} = alert_channel) do
    AppRepo.delete(alert_channel)
  end

  # Status Page functions

  @doc """
  Returns the list of status pages for an organization.
  """
  def list_status_pages(organization_id) do
    StatusPage
    |> where([sp], sp.organization_id == ^organization_id)
    |> order_by([sp], asc: sp.name)
    |> AppRepo.all()
  end

  @doc """
  Gets a status page by slug.
  """
  def get_status_page_by_slug!(slug) do
    StatusPage
    |> where([sp], sp.slug == ^slug)
    |> preload([sp], [:monitors, :status_page_monitors])
    |> AppRepo.one!()
  end

  @doc """
  Gets a status page by slug with monitor status data.
  """
  def get_status_page_with_status!(slug) do
    status_page = get_status_page_by_slug!(slug)

    # Get monitors with their latest checks
    monitors =
      from(m in Monitor,
        join: spm in StatusPageMonitor,
        on: spm.monitor_id == m.id,
        where: spm.status_page_id == ^status_page.id,
        order_by: [asc: spm.sort_order, asc: m.name]
      )
      |> AppRepo.all()

    monitor_ids = Enum.map(monitors, & &1.id)

    latest_checks =
      if Enum.any?(monitor_ids) do
        subquery =
          from mc in MonitorCheck,
            where: mc.monitor_id in ^monitor_ids,
            order_by: [desc: mc.checked_at],
            distinct: mc.monitor_id,
            select: mc

        AppRepo.all(subquery)
        |> Enum.group_by(& &1.monitor_id)
      else
        %{}
      end

    monitors_with_status =
      Enum.map(monitors, fn monitor ->
        latest_check = Map.get(latest_checks, monitor.id, []) |> List.first()
        %{monitor | monitor_checks: if(latest_check, do: [latest_check], else: [])}
      end)

    %{status_page | monitors: monitors_with_status}
  end

  @doc """
  Gets a single status page.
  """
  def get_status_page!(id) do
    StatusPage
    |> preload(status_page_monitors: :monitor)
    |> AppRepo.get!(id)
  end

  @doc """
  Gets a status page for an organization.
  Returns nil if not found or doesn't belong to the organization.
  """
  def get_organization_status_page(organization_id, status_page_id) do
    StatusPage
    |> where([sp], sp.id == ^status_page_id and sp.organization_id == ^organization_id)
    |> AppRepo.one()
  end

  @doc """
  Creates a status page.
  """
  def create_status_page(attrs) do
    %StatusPage{}
    |> StatusPage.changeset(attrs)
    |> AppRepo.insert()
  end

  @doc """
  Updates a status page.
  """
  def update_status_page(%StatusPage{} = status_page, attrs) do
    status_page
    |> StatusPage.changeset(attrs)
    |> AppRepo.update()
  end

  @doc """
  Deletes a status page.
  """
  def delete_status_page(%StatusPage{} = status_page) do
    AppRepo.delete(status_page)
  end

  @doc """
  Adds a monitor to a status page.
  """
  def add_monitor_to_status_page(status_page_id, monitor_id, attrs \\ %{}) do
    attrs = Map.merge(attrs, %{status_page_id: status_page_id, monitor_id: monitor_id})

    %StatusPageMonitor{}
    |> StatusPageMonitor.changeset(attrs)
    |> AppRepo.insert()
  end

  @doc """
  Removes a monitor from a status page.
  """
  def remove_monitor_from_status_page(status_page_id, monitor_id) do
    StatusPageMonitor
    |> where([spm], spm.status_page_id == ^status_page_id and spm.monitor_id == ^monitor_id)
    |> AppRepo.delete_all()
  end

  @doc """
  Gets status page monitors for a status page.
  """
  def get_status_page_monitors(status_page) do
    StatusPageMonitor
    |> where([spm], spm.status_page_id == ^status_page.id)
    |> AppRepo.all()
  end

  @doc """
  Syncs the monitors assigned to a status page.
  Removes monitors not in the list and adds new ones.
  """
  def sync_status_page_monitors(%StatusPage{} = status_page, monitor_ids) when is_list(monitor_ids) do
    current_ids =
      StatusPageMonitor
      |> where([spm], spm.status_page_id == ^status_page.id)
      |> select([spm], spm.monitor_id)
      |> AppRepo.all()
      |> Enum.map(&to_string/1)

    monitor_ids = Enum.map(monitor_ids, &to_string/1)

    to_remove = current_ids -- monitor_ids
    to_add = monitor_ids -- current_ids

    for mid <- to_remove, do: remove_monitor_from_status_page(status_page.id, mid)

    to_add
    |> Enum.with_index()
    |> Enum.each(fn {mid, idx} ->
      add_monitor_to_status_page(status_page.id, mid, %{sort_order: length(current_ids) + idx})
    end)

    :ok
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking status page changes.
  """
  def change_status_page(%StatusPage{} = status_page, attrs \\ %{}) do
    StatusPage.changeset(status_page, attrs)
  end

  @doc """
  Gets a status page by slug (non-raising version).
  Returns nil if not found.
  """
  def get_status_page_by_slug(slug) do
    StatusPage
    |> where([sp], sp.slug == ^slug)
    |> where([sp], sp.is_public == true)
    |> AppRepo.one()
  end

  @doc """
  Calculates the uptime percentage for a status page over the given number of days.
  Returns a float between 0 and 100.
  """
  def get_status_page_uptime(status_page_id, days \\ 30) do
    # Get all monitor IDs for this status page
    monitor_ids =
      StatusPageMonitor
      |> where([spm], spm.status_page_id == ^status_page_id)
      |> select([spm], spm.monitor_id)
      |> AppRepo.all()

    if Enum.empty?(monitor_ids) do
      100.0
    else
      since = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

      # Calculate weighted uptime based on number of checks
      {total_up, total_checks} =
        MonitorCheck
        |> where([mc], mc.monitor_id in ^monitor_ids)
        |> where([mc], mc.checked_at >= ^since)
        |> select([mc], {count(fragment("CASE WHEN ? = 'up' THEN 1 END", mc.status)), count()})
        |> AppRepo.one()

      if total_checks > 0 do
        (total_up || 0) / total_checks * 100.0
      else
        100.0
      end
    end
  end

  @doc """
  Gets the overall operational status for a status page.
  Returns one of: :operational, :degraded, :partial_outage, :major_outage
  """
  def get_status_page_status(status_page_id) do
    # Get all monitors for this status page
    monitor_ids =
      StatusPageMonitor
      |> where([spm], spm.status_page_id == ^status_page_id)
      |> select([spm], spm.monitor_id)
      |> AppRepo.all()

    if Enum.empty?(monitor_ids) do
      :operational
    else
      # Get the latest check status for each monitor
      statuses =
        Enum.map(monitor_ids, fn monitor_id ->
          MonitorCheck
          |> where([mc], mc.monitor_id == ^monitor_id)
          |> order_by([mc], desc: mc.checked_at)
          |> limit(1)
          |> select([mc], mc.status)
          |> AppRepo.one()
        end)
        |> Enum.reject(&is_nil/1)

      if Enum.empty?(statuses) do
        :operational
      else
        down_count = Enum.count(statuses, &(&1 == "down"))
        total = length(statuses)
        down_ratio = down_count / total

        cond do
          down_ratio == 0 -> :operational
          down_ratio < 0.25 -> :degraded
          down_ratio < 0.75 -> :partial_outage
          true -> :major_outage
        end
      end
    end
  end

  # Status page subscriber functions

  @doc """
  Lists all verified subscribers for a status page.
  """
  def list_status_page_subscribers(status_page_id) do
    StatusPageSubscriber
    |> where([s], s.status_page_id == ^status_page_id and s.verified == true)
    |> order_by([s], desc: s.subscribed_at)
    |> AppRepo.all()
  end

  @doc """
  Creates a new subscriber (unverified).
  """
  def subscribe_to_status_page(status_page_id, email) do
    attrs = %{status_page_id: status_page_id, email: email}

    %StatusPageSubscriber{}
    |> StatusPageSubscriber.changeset(attrs)
    |> AppRepo.insert()
  end

  @doc """
  Gets a subscriber by verification token.
  """
  def get_subscriber_by_verification_token(token) do
    StatusPageSubscriber
    |> where([s], s.verification_token == ^token)
    |> AppRepo.one()
  end

  @doc """
  Gets a subscriber by unsubscribe token.
  """
  def get_subscriber_by_unsubscribe_token(token) do
    StatusPageSubscriber
    |> where([s], s.unsubscribe_token == ^token)
    |> AppRepo.one()
  end

  @doc """
  Verifies a subscriber's email address.
  """
  def verify_subscriber(%StatusPageSubscriber{} = subscriber) do
    subscriber
    |> StatusPageSubscriber.verify_changeset()
    |> AppRepo.update()
  end

  @doc """
  Deletes a subscriber (unsubscribe).
  """
  def unsubscribe(%StatusPageSubscriber{} = subscriber) do
    AppRepo.delete(subscriber)
  end

  @doc """
  Checks if an email is already subscribed to a status page.
  """
  def subscriber_exists?(status_page_id, email) do
    StatusPageSubscriber
    |> where([s], s.status_page_id == ^status_page_id and s.email == ^email)
    |> AppRepo.exists?()
  end

  # Incident management functions

  @doc """
  Returns the list of incidents for an organization.
  """
  def list_incidents(organization_id) do
    from(i in Incident,
      where: i.organization_id == ^organization_id,
      order_by: [desc: i.started_at],
      preload: [:monitor, :incident_updates]
    )
    |> AppRepo.all()
  end

  @doc """
  Returns the list of ongoing incidents for an organization.
  """
  def list_ongoing_incidents(organization_id) do
    from(i in Incident,
      where: i.organization_id == ^organization_id and i.status == "ongoing",
      order_by: [desc: i.started_at],
      preload: [:monitor, :incident_updates]
    )
    |> AppRepo.all()
  end

  @doc """
  Gets a single incident.
  """
  def get_incident!(id), do: AppRepo.get!(Incident, id)

  @doc """
  Gets a single incident with preloaded associations.
  """
  def get_incident_with_updates!(id) do
    Incident
    |> where([i], i.id == ^id)
    |> preload([:monitor, incident_updates: [:user]])
    |> AppRepo.one!()
  end

  @doc """
  Creates an incident update.
  """
  def create_incident_update(attrs) do
    %IncidentUpdate{}
    |> IncidentUpdate.changeset(attrs)
    |> AppRepo.insert()
  end

  @doc """
  Updates an incident update.
  """
  def update_incident_update(%IncidentUpdate{} = incident_update, attrs) do
    incident_update
    |> IncidentUpdate.changeset(attrs)
    |> AppRepo.update()
  end

  @doc """
  Deletes an incident update.
  """
  def delete_incident_update(%IncidentUpdate{} = incident_update) do
    AppRepo.delete(incident_update)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking incident update changes.
  """
  def change_incident_update(%IncidentUpdate{} = incident_update, attrs \\ %{}) do
    IncidentUpdate.changeset(incident_update, attrs)
  end

  @doc """
  Manually resolves an incident.
  """
  def manually_resolve_incident(%Incident{} = incident) do
    resolved_at = DateTime.utc_now()
    duration = DateTime.diff(resolved_at, incident.started_at)

    incident
    |> Incident.changeset(%{
      status: "resolved",
      resolved_at: resolved_at,
      duration: duration
    })
    |> AppRepo.update()
  end

  @doc """
  Manually creates an incident for a monitor.
  """
  def manually_create_incident(monitor_id, attrs) do
    attrs =
      Map.merge(attrs, %{
        "monitor_id" => monitor_id,
        "started_at" => DateTime.utc_now(),
        "status" => "ongoing"
      })

    %Incident{}
    |> Incident.changeset(attrs)
    |> AppRepo.insert()
  end

  # Dashboard functions

  @doc """
  Returns dashboard stats for an organization.
  """
  def get_dashboard_stats(organization_id) do
    alias Uptrack.Cache

    Cache.fetch(Cache.dashboard_stats_key(organization_id), [ttl: Cache.ttl_short()], fn ->
      total_monitors =
        Monitor
        |> where([m], m.organization_id == ^organization_id)
        |> AppRepo.aggregate(:count, :id)

      active_monitors =
        Monitor
        |> where([m], m.organization_id == ^organization_id and m.status == "active")
        |> AppRepo.aggregate(:count, :id)

      ongoing_incidents =
        Incident
        |> where([i], i.organization_id == ^organization_id and i.status == "ongoing")
        |> AppRepo.aggregate(:count, :id)

      recent_incidents_count =
        Incident
        |> where([i], i.organization_id == ^organization_id and i.started_at >= ago(7, "day"))
        |> AppRepo.aggregate(:count, :id)

      %{
        total_monitors: total_monitors,
        active_monitors: active_monitors,
        ongoing_incidents: ongoing_incidents,
        recent_incidents: recent_incidents_count
      }
    end)
  end

  @doc """
  Returns monitors with their latest status for dashboard.
  """
  def get_dashboard_monitors(organization_id) do
    monitors =
      Monitor
      |> where([m], m.organization_id == ^organization_id)
      |> order_by([m], desc: m.inserted_at)
      |> AppRepo.all()

    # Manually preload the latest check for each monitor
    monitor_ids = Enum.map(monitors, & &1.id)

    latest_checks =
      if Enum.any?(monitor_ids) do
        subquery =
          from mc in MonitorCheck,
            where: mc.monitor_id in ^monitor_ids,
            order_by: [desc: mc.checked_at],
            distinct: mc.monitor_id,
            select: mc

        AppRepo.all(subquery)
        |> Enum.group_by(& &1.monitor_id)
      else
        %{}
      end

    Enum.map(monitors, fn monitor ->
      %{monitor | monitor_checks: Map.get(latest_checks, monitor.id, [])}
    end)
  end

  # Analytics functions

  @doc """
  Returns uptime data for a monitor over the last N days for charting.
  """
  def get_uptime_chart_data(monitor_id, days \\ 30) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    # Get checks grouped by day
    query =
      from mc in MonitorCheck,
        where: mc.monitor_id == ^monitor_id and mc.checked_at >= ^cutoff_date,
        select: %{
          date: fragment("DATE(?)", mc.checked_at),
          total: count(mc.id),
          up: count(mc.id) |> filter(mc.status == "up")
        },
        group_by: fragment("DATE(?)", mc.checked_at),
        order_by: [asc: fragment("DATE(?)", mc.checked_at)]

    daily_stats = AppRepo.all(query)

    # Fill in missing dates with 100% uptime
    start_date = Date.add(Date.utc_today(), -days)

    Enum.map(0..(days - 1), fn day_offset ->
      date = Date.add(start_date, day_offset)

      case Enum.find(daily_stats, &(&1.date == date)) do
        nil ->
          %{date: date, uptime: 100.0, total: 0}

        stat ->
          %{
            date: stat.date,
            uptime:
              if(stat.total > 0, do: (stat.up / stat.total * 100) |> Float.round(2), else: 100.0),
            total: stat.total
          }
      end
    end)
  end

  @doc """
  Returns response time trends for a monitor over the last N days.
  """
  def get_response_time_trends(monitor_id, days \\ 30) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    query =
      from mc in MonitorCheck,
        where:
          mc.monitor_id == ^monitor_id and mc.checked_at >= ^cutoff_date and
            not is_nil(mc.response_time),
        select: %{
          date: fragment("DATE(?)", mc.checked_at),
          avg_response_time: avg(mc.response_time),
          min_response_time: min(mc.response_time),
          max_response_time: max(mc.response_time),
          total_checks: count(mc.id)
        },
        group_by: fragment("DATE(?)", mc.checked_at),
        order_by: [asc: fragment("DATE(?)", mc.checked_at)]

    AppRepo.all(query)
    |> Enum.map(fn stat ->
      %{
        date: stat.date,
        avg: to_float(stat.avg_response_time, 0) |> Float.round(2),
        min: stat.min_response_time || 0,
        max: stat.max_response_time || 0,
        total_checks: stat.total_checks
      }
    end)
  end

  @doc """
  Returns incident statistics for a monitor.
  """
  def get_incident_stats(monitor_id, days \\ 30) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    incidents_query =
      from i in Incident,
        where: i.monitor_id == ^monitor_id and i.started_at >= ^cutoff_date

    total_incidents = incidents_query |> AppRepo.aggregate(:count, :id)

    ongoing_incidents =
      incidents_query
      |> where([i], i.status == "ongoing")
      |> AppRepo.aggregate(:count, :id)

    resolved_incidents =
      incidents_query
      |> where([i], i.status == "resolved")
      |> AppRepo.aggregate(:count, :id)

    # Average incident duration for resolved incidents
    avg_duration_query =
      from i in Incident,
        where: i.monitor_id == ^monitor_id and i.status == "resolved" and not is_nil(i.duration),
        select: avg(i.duration)

    avg_duration = AppRepo.one(avg_duration_query) |> to_float(0)

    # MTTR (Mean Time To Recovery) in minutes
    mttr_minutes = if avg_duration > 0, do: Float.round(avg_duration / 60, 2), else: 0

    %{
      total_incidents: total_incidents,
      ongoing_incidents: ongoing_incidents,
      resolved_incidents: resolved_incidents,
      mttr_minutes: mttr_minutes
    }
  end

  @doc """
  Returns overall uptime for all monitors of an organization.
  """
  def get_organization_overall_uptime(organization_id, days \\ 30) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    query =
      from mc in MonitorCheck,
        join: m in Monitor,
        on: mc.monitor_id == m.id,
        where: m.organization_id == ^organization_id and mc.checked_at >= ^cutoff_date,
        select: %{
          total: count(mc.id),
          up: count(mc.id) |> filter(mc.status == "up")
        }

    case AppRepo.one(query) do
      %{total: 0} -> 100.0
      %{total: total, up: up} -> (up / total * 100) |> Float.round(2)
    end
  end

  # Cache invalidation helpers

  defp invalidate_org_cache(org_id) do
    alias Uptrack.Cache
    Cache.invalidate(Cache.dashboard_stats_key(org_id))
    Cache.invalidate_prefix("dashboard_analytics:#{org_id}:")
    Cache.invalidate_prefix("org_trends:#{org_id}:")
  end

  defp invalidate_monitor_cache(monitor_id) do
    alias Uptrack.Cache
    Cache.invalidate_prefix("monitor_analytics:#{monitor_id}:")
  end

  defp to_float(%Decimal{} = d, _default), do: Decimal.to_float(d)
  defp to_float(nil, default), do: default
  defp to_float(f, _default) when is_float(f), do: f
  defp to_float(i, _default) when is_integer(i), do: i * 1.0
end
