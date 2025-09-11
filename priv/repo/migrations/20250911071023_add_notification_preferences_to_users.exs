defmodule Uptrack.Repo.Migrations.AddNotificationPreferencesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :notification_preferences, :map,
        default: %{
          # Email notification settings
          email_enabled: true,
          email_on_incident_started: true,
          email_on_incident_resolved: true,
          email_on_monitor_down: true,
          email_on_monitor_up: true,

          # Notification frequency settings
          # immediate, hourly, daily
          notification_frequency: "immediate",
          quiet_hours_enabled: false,
          quiet_hours_start: "22:00",
          quiet_hours_end: "08:00",
          quiet_hours_timezone: "UTC",

          # Monitor-specific settings
          send_ssl_expiry_alerts: true,
          ssl_expiry_days_before: 30,

          # Weekly/Monthly summary reports
          weekly_summary_enabled: true,
          monthly_summary_enabled: true,

          # Incident escalation
          escalation_enabled: false,
          escalation_delay_minutes: 30
        }
    end
  end
end
