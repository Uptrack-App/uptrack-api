defmodule Uptrack.AppRepo.Migrations.AddVlTraceIdToIncidents do
  use Ecto.Migration

  def change do
    alter table("incidents", prefix: "app") do
      add :vl_trace_id, :uuid, null: true
    end

    # Non-unique btree for "fetch the events belonging to this incident"
    # lookups; we query VL by trace_id, not Postgres, but keep the index
    # for the rare direct join.
    create index("incidents", [:vl_trace_id], prefix: "app", where: "vl_trace_id IS NOT NULL")
  end
end
