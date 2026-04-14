defmodule Mix.Tasks.Enforce30sCap do
  @moduledoc """
  Enforces the 10-monitor cap on 30s intervals for free plan organizations.

  For any free org with more than 10 monitors at 30s, the excess monitors
  (ordered by most recently created) are updated to 60s.

  ## Usage

      # Dry run — shows what would change
      mix enforce_30s_cap --dry-run

      # Live run
      mix enforce_30s_cap

  """

  use Mix.Task

  @shortdoc "Downgrade excess 30s monitors to 60s for free plan orgs"
  @cap 10

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    dry_run = "--dry-run" in args
    if dry_run, do: Mix.shell().info("=== DRY RUN — no changes will be made ===\n")

    import Ecto.Query
    alias Uptrack.AppRepo
    alias Uptrack.Organizations.Organization
    alias Uptrack.Monitoring.Monitor

    free_org_ids =
      Organization
      |> where([o], o.plan == "free")
      |> select([o], o.id)
      |> AppRepo.all()

    Mix.shell().info("Found #{length(free_org_ids)} free plan organizations\n")

    total_updated = Enum.reduce(free_org_ids, 0, fn org_id, acc ->
      monitors_30s =
        Monitor
        |> where([m], m.organization_id == ^org_id and m.interval <= 30 and m.status != "deleted")
        |> order_by([m], asc: m.inserted_at)
        |> AppRepo.all()

      count = length(monitors_30s)

      if count <= @cap do
        acc
      else
        org = AppRepo.get(Organization, org_id)
        excess = Enum.drop(monitors_30s, @cap)

        Mix.shell().info("Org #{org.name} (#{org_id}): #{count} at 30s — downgrading #{length(excess)}")

        Enum.each(excess, fn m ->
          if dry_run do
            Mix.shell().info("  [DRY] Would update: #{m.name}")
          else
            Uptrack.Monitoring.update_monitor(m, %{interval: 60})
            Mix.shell().info("  Updated: #{m.name}")
          end
        end)

        acc + length(excess)
      end
    end)

    Mix.shell().info("\n#{if dry_run, do: "Would update", else: "Updated"}: #{total_updated} monitors")
  end
end
