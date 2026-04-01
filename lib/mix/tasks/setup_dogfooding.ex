defmodule Mix.Tasks.SetupDogfooding do
  @moduledoc """
  Creates self-monitoring monitors for Uptrack's own infrastructure.

  Finds the first organization (or one named "Uptrack") and its owner,
  then creates monitors for uptrack.app and api.uptrack.app.

  ## Usage

      mix setup_dogfooding

  Idempotent: skips monitors whose names already exist in the organization.
  """

  use Mix.Task

  @shortdoc "Set up Uptrack self-monitoring (dogfooding)"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    alias Uptrack.{Organizations, Monitoring, Accounts}
    alias Uptrack.AppRepo
    import Ecto.Query

    # Find the Uptrack organization, or fall back to the first one
    orgs = Organizations.list_organizations()

    org =
      Enum.find(orgs, List.first(orgs), fn o ->
        String.downcase(o.name) =~ "uptrack"
      end)

    if is_nil(org) do
      Mix.shell().error("No organizations found. Please create one first.")
      exit({:shutdown, 1})
    end

    Mix.shell().info("Using organization: #{org.name} (#{org.id})")

    # Find the owner user for this organization
    user =
      Accounts.User
      |> where([u], u.organization_id == ^org.id)
      |> order_by([u], asc: u.inserted_at)
      |> limit(1)
      |> AppRepo.one()

    if is_nil(user) do
      Mix.shell().error("No users found for organization #{org.name}.")
      exit({:shutdown, 1})
    end

    Mix.shell().info("Using user: #{user.email} (#{user.id})")

    # Get existing monitor names to skip duplicates
    existing =
      Monitoring.list_monitors(org.id)
      |> Enum.map(& &1.name)
      |> MapSet.new()

    monitors = [
      %{
        name: "Uptrack Homepage",
        url: "https://uptrack.app",
        monitor_type: "http",
        interval: 60,
        timeout: 30,
        status: "active",
        description: "Main landing page health check",
        organization_id: org.id,
        user_id: user.id
      },
      %{
        name: "Uptrack API",
        url: "https://api.uptrack.app/api/monitors",
        monitor_type: "http",
        interval: 60,
        timeout: 30,
        status: "active",
        description: "API endpoint reachability (expects 401 Unauthorized)",
        settings: %{"expected_status_code" => 401},
        organization_id: org.id,
        user_id: user.id
      },
      %{
        name: "Uptrack SSL",
        url: "https://uptrack.app",
        monitor_type: "ssl",
        interval: 21600,
        timeout: 30,
        status: "active",
        description: "SSL certificate expiry monitoring for uptrack.app",
        organization_id: org.id,
        user_id: user.id
      },
      %{
        name: "API SSL",
        url: "https://api.uptrack.app",
        monitor_type: "ssl",
        interval: 21600,
        timeout: 30,
        status: "active",
        description: "SSL certificate expiry monitoring for api.uptrack.app",
        organization_id: org.id,
        user_id: user.id
      },
      %{
        name: "Uptrack DNS",
        url: "uptrack.app",
        monitor_type: "dns",
        interval: 3600,
        timeout: 30,
        status: "active",
        description: "DNS A record resolution for uptrack.app",
        settings: %{"dns_record_type" => "A"},
        organization_id: org.id,
        user_id: user.id
      },
      %{
        name: "Status Page",
        url: "https://uptrack.app/status/uptrack",
        monitor_type: "http",
        interval: 180,
        timeout: 30,
        status: "active",
        description: "Public status page availability",
        organization_id: org.id,
        user_id: user.id
      }
    ]

    Enum.each(monitors, fn attrs ->
      if MapSet.member?(existing, attrs.name) do
        Mix.shell().info("  Skipped (exists): #{attrs.name}")
      else
        case Monitoring.create_monitor(attrs) do
          {:ok, monitor} ->
            Mix.shell().info("  Created: #{monitor.name} (#{monitor.monitor_type}, #{monitor.interval}s)")

          {:error, changeset} ->
            Mix.shell().error("  Failed: #{attrs.name} — #{inspect(changeset.errors)}")
        end
      end
    end)

    Mix.shell().info("\nDogfooding setup complete!")
  end
end
