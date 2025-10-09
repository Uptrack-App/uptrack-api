defmodule Uptrack.Monitoring.StatusPageMonitor do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Monitoring.{StatusPage, Monitor}

  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "status_page_monitors" do
    field :display_name, :string
    field :sort_order, :integer, default: 0

    belongs_to :status_page, StatusPage
    belongs_to :monitor, Monitor

    timestamps()
  end

  @doc false
  def changeset(status_page_monitor, attrs) do
    status_page_monitor
    |> cast(attrs, [:display_name, :sort_order, :status_page_id, :monitor_id])
    |> validate_required([:status_page_id, :monitor_id])
    |> validate_length(:display_name, max: 255)
    |> validate_number(:sort_order, greater_than_or_equal_to: 0)
    |> unique_constraint([:status_page_id, :monitor_id])
  end
end
