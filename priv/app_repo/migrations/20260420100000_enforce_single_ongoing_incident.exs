defmodule Uptrack.AppRepo.Migrations.EnforceSingleOngoingIncident do
  use Ecto.Migration

  def up do
    # Collapse duplicate ongoing incidents per monitor: keep the oldest row
    # (closest to the actual first failure) and resolve the rest so the
    # partial unique index below can be created.
    execute("""
    WITH ranked AS (
      SELECT id,
             started_at,
             ROW_NUMBER() OVER (
               PARTITION BY monitor_id
               ORDER BY started_at ASC, inserted_at ASC, id ASC
             ) AS rn
      FROM app.incidents
      WHERE status = 'ongoing'
    )
    UPDATE app.incidents i
    SET status = 'resolved',
        resolved_at = NOW(),
        duration = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - i.started_at))::int),
        updated_at = NOW()
    FROM ranked r
    WHERE i.id = r.id AND r.rn > 1;
    """)

    create unique_index(:incidents, [:monitor_id],
             prefix: "app",
             where: "status = 'ongoing'",
             name: :incidents_one_ongoing_per_monitor_idx
           )
  end

  def down do
    drop index(:incidents, [:monitor_id],
           prefix: "app",
           name: :incidents_one_ongoing_per_monitor_idx
         )
  end
end
