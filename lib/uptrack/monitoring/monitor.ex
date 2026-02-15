defmodule Uptrack.Monitoring.Monitor do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Accounts.User
  alias Uptrack.Organizations.Organization
  alias Uptrack.Monitoring.{MonitorCheck, Incident}

  @monitor_types ~w(http https tcp ping keyword ssl heartbeat)
  @statuses ~w(active paused disabled)

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "monitors" do
    field :name, :string
    field :url, :string
    field :monitor_type, :string, default: "http"
    field :interval, :integer, default: 300
    field :timeout, :integer, default: 30
    field :status, :string, default: "active"
    field :description, :string
    field :alert_contacts, {:array, :string}, default: []
    field :settings, :map, default: %{}
    field :consecutive_failures, :integer, default: 0
    field :confirmation_threshold, :integer, default: 2
    field :uptime_percentage, :float, virtual: true

    belongs_to :organization, Organization
    belongs_to :user, User
    has_many :monitor_checks, MonitorCheck, preload_order: [desc: :checked_at]
    has_many :incidents, Incident, preload_order: [desc: :started_at]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(monitor, attrs) do
    monitor
    |> cast(attrs, [
      :name,
      :url,
      :monitor_type,
      :interval,
      :timeout,
      :status,
      :description,
      :alert_contacts,
      :settings,
      :confirmation_threshold,
      :organization_id,
      :user_id
    ])
    |> validate_required([:name, :url, :organization_id, :user_id])
    |> validate_inclusion(:monitor_type, @monitor_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:interval, greater_than_or_equal_to: 30)
    |> validate_number(:timeout, greater_than_or_equal_to: 5, less_than_or_equal_to: 300)
    |> validate_number(:confirmation_threshold, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_url()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc false
  def create_changeset(monitor, attrs) do
    monitor
    |> changeset(attrs)
    |> put_change(:status, "active")
  end

  defp validate_url(changeset) do
    monitor_type = get_field(changeset, :monitor_type)

    validate_change(changeset, :url, fn :url, url ->
      cond do
        # HTTP/HTTPS monitors require valid URL
        monitor_type in ["http", "https", "keyword", "ssl"] ->
          case URI.parse(url) do
            %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
              []

            %URI{host: host} when not is_nil(host) ->
              # Accept bare hostname for SSL checks
              []

            _ ->
              [url: "must be a valid URL or hostname"]
          end

        # TCP/Ping monitors accept host:port or just host
        monitor_type in ["tcp", "ping"] ->
          if String.match?(url, ~r/^[a-zA-Z0-9\-\.]+(\:\d+)?$/) do
            []
          else
            [url: "must be a valid hostname or host:port"]
          end

        # Heartbeat monitors don't need a URL (they generate one)
        monitor_type == "heartbeat" ->
          []

        true ->
          []
      end
    end)
  end

  def monitor_types, do: @monitor_types
  def statuses, do: @statuses
end
