# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Idempotent: safe to run multiple times (checks for existing data first).

alias Uptrack.{Accounts, Organizations, Monitoring, Alerting}
alias Uptrack.AppRepo

# Only seed if the database is empty
if Organizations.list_organizations() == [] do
  IO.puts("Seeding database...")

  # --- Organization ---
  {:ok, org} =
    Organizations.create_organization(%{
      name: "Acme Inc.",
      slug: "acme-inc",
      plan: "pro"
    })

  IO.puts("  Created organization: #{org.name}")

  # --- Admin User ---
  {:ok, admin} =
    Accounts.create_user(%{
      email: "admin@example.com",
      name: "Admin User",
      password: "password123456",
      organization_id: org.id,
      role: :owner
    })

  IO.puts("  Created admin user: #{admin.email}")

  # --- Monitors ---
  monitors =
    [
      %{
        name: "Company Website",
        url: "https://example.com",
        monitor_type: "http",
        interval: 300,
        timeout: 30,
        status: "active",
        description: "Main company website",
        organization_id: org.id,
        user_id: admin.id
      },
      %{
        name: "API Server",
        url: "https://api.example.com/health",
        monitor_type: "http",
        interval: 60,
        timeout: 10,
        status: "active",
        description: "REST API health endpoint",
        organization_id: org.id,
        user_id: admin.id
      },
      %{
        name: "Database Server",
        url: "db.example.com:5432",
        monitor_type: "tcp",
        interval: 120,
        timeout: 15,
        status: "active",
        description: "PostgreSQL database port check",
        organization_id: org.id,
        user_id: admin.id
      },
      %{
        name: "SSL Certificate",
        url: "https://example.com",
        monitor_type: "ssl",
        interval: 3600,
        timeout: 30,
        status: "active",
        description: "SSL certificate expiry monitoring",
        organization_id: org.id,
        user_id: admin.id
      },
      %{
        name: "Keyword Check",
        url: "https://example.com",
        monitor_type: "keyword",
        interval: 600,
        timeout: 30,
        status: "active",
        description: "Checks for expected content on homepage",
        settings: %{"keyword" => "Welcome", "should_contain" => true},
        organization_id: org.id,
        user_id: admin.id
      }
    ]

  created_monitors =
    Enum.map(monitors, fn attrs ->
      {:ok, monitor} = Monitoring.create_monitor(attrs)
      IO.puts("  Created monitor: #{monitor.name} (#{monitor.monitor_type})")
      monitor
    end)

  # --- Alert Channels ---
  alert_channels =
    [
      %{
        name: "Admin Email",
        type: "email",
        config: %{"email" => "admin@example.com"},
        is_active: true,
        organization_id: org.id,
        user_id: admin.id
      },
      %{
        name: "Ops Webhook",
        type: "webhook",
        config: %{
          "url" => "https://hooks.example.com/alerts",
          "secret" => "whsec_example_secret_key"
        },
        is_active: true,
        organization_id: org.id,
        user_id: admin.id
      }
    ]

  Enum.each(alert_channels, fn attrs ->
    {:ok, channel} = Alerting.create_alert_channel(attrs)
    IO.puts("  Created alert channel: #{channel.name} (#{channel.type})")
  end)

  # --- Status Page ---
  {:ok, status_page} =
    Monitoring.create_status_page(%{
      name: "Acme Status",
      slug: "acme-status",
      description: "Current status of Acme services",
      is_public: true,
      allow_subscriptions: true,
      default_language: "en",
      organization_id: org.id,
      user_id: admin.id
    })

  IO.puts("  Created status page: #{status_page.name}")

  # Add first two monitors to the status page
  [website, api | _] = created_monitors

  Enum.each([website, api], fn monitor ->
    Monitoring.add_monitor_to_status_page(status_page.id, monitor.id)
    IO.puts("  Added #{monitor.name} to status page")
  end)

  # --- Sample Incident (resolved) ---
  started_at = DateTime.utc_now() |> DateTime.add(-3600, :second)
  resolved_at = DateTime.utc_now() |> DateTime.add(-1800, :second)

  {:ok, incident} =
    Monitoring.create_incident(%{
      started_at: started_at,
      resolved_at: resolved_at,
      status: "resolved",
      cause: "Upstream provider outage",
      duration: 1800,
      organization_id: org.id,
      monitor_id: website.id
    })

  IO.puts("  Created sample incident (resolved, 30min duration)")

  IO.puts("\nSeeding complete!")
  IO.puts("  Login: admin@example.com / password123456")
else
  IO.puts("Database already seeded, skipping.")
end
