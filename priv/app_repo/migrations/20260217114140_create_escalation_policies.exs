defmodule Uptrack.AppRepo.Migrations.CreateEscalationPolicies do
  use Ecto.Migration

  def change do
    create table("escalation_policies", prefix: "app", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, prefix: "app", type: :binary_id), null: false
      add :name, :string, null: false
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create index("escalation_policies", [:organization_id], prefix: "app")

    create table("escalation_steps", prefix: "app", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :escalation_policy_id, references(:escalation_policies, prefix: "app", type: :binary_id, on_delete: :delete_all), null: false
      add :alert_channel_id, references(:alert_channels, prefix: "app", type: :binary_id), null: false
      add :step_order, :integer, null: false
      add :delay_minutes, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index("escalation_steps", [:escalation_policy_id, :step_order], prefix: "app")

    # Add escalation_policy_id to monitors
    alter table("monitors", prefix: "app") do
      add :escalation_policy_id, references(:escalation_policies, prefix: "app", type: :binary_id, on_delete: :nilify_all)
    end

    # Add acknowledged_at to incidents for escalation cancellation
    alter table("incidents", prefix: "app") do
      add :acknowledged_at, :utc_datetime
      add :acknowledged_by_id, references(:users, prefix: "app", type: :binary_id)
    end
  end
end
