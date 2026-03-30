defmodule Uptrack.Reports.WeeklyReportWorker do
  @moduledoc """
  Oban cron worker that sends weekly uptime reports every Monday at 9am UTC.

  Fans out per-organization: fetches all orgs on Team+ plans,
  gathers monitoring data, builds report, and emails each user.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Uptrack.{Organizations, Monitoring, Billing}
  alias Uptrack.Reports.{ReportBuilder, ReportEmail}

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("WeeklyReportWorker: starting weekly report generation")

    organizations = Organizations.list_organizations()

    results =
      organizations
      |> Enum.filter(&report_enabled?/1)
      |> Enum.map(&send_org_report/1)

    sent = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :error))

    Logger.info("WeeklyReportWorker: sent #{sent} reports, #{failed} failed")

    if failed > 0 do
      {:error, "#{failed} org report(s) failed — check logs for details"}
    else
      :ok
    end
  end

  defp report_enabled?(org) do
    # Weekly reports are a Team+ feature
    Billing.can_use_feature?(org, :weekly_reports)
  end

  defp send_org_report(org) do
    monitors = Monitoring.list_monitors(org.id)

    if monitors == [] do
      :skip
    else
      period_start = Date.add(Date.utc_today(), -7)
      period_end = Date.utc_today()
      period = "#{Calendar.strftime(period_start, "%b %d")} – #{Calendar.strftime(period_end, "%b %d, %Y")}"

      uptime_data =
        monitors
        |> Enum.flat_map(fn monitor ->
          Monitoring.get_uptime_chart_data(monitor.id, 7)
          |> Enum.map(&Map.put(&1, :monitor_id, monitor.id))
        end)

      incident_count = Monitoring.count_recent_incidents(org.id, 7)

      report =
        ReportBuilder.build_summary(%{
          monitors: monitors,
          uptime_data: uptime_data,
          incident_count: incident_count,
          period: period
        })

      # Send to all users in the org (not notify_only)
      users = Uptrack.Teams.list_members(org.id)

      Enum.each(users, fn user ->
        if user.role != :notify_only do
          case ReportEmail.deliver(user, report) do
            {:ok, _} -> Logger.info("Weekly report sent to #{user.email}")
            {:error, reason} -> Logger.error("Failed to send weekly report to #{user.email}: #{inspect(reason)}")
          end
        end
      end)

      :ok
    end
  rescue
    e ->
      Logger.error("WeeklyReportWorker: error for org #{org.id}: #{Exception.format(:error, e, __STACKTRACE__)}")
      :error
  end
end
