defmodule Uptrack.Monitoring.Region do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Monitoring.{MonitorRegion, MonitorCheck}

  @providers ~w(hetzner vultr linode contabo digitalocean)

  @schema_prefix "app"
  schema "regions" do
    field :code, :string
    field :name, :string
    field :provider, :string, default: "hetzner"
    field :is_active, :boolean, default: true
    field :endpoint_url, :string
    field :metadata, :map, default: %{}

    has_many :monitor_regions, MonitorRegion
    has_many :monitor_checks, MonitorCheck

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(region, attrs) do
    region
    |> cast(attrs, [:code, :name, :provider, :is_active, :endpoint_url, :metadata])
    |> validate_required([:code, :name, :provider])
    |> validate_inclusion(:provider, @providers)
    |> validate_format(:code, ~r/^[a-z0-9-]+$/, message: "must contain only lowercase letters, numbers, and hyphens")
    |> unique_constraint(:code)
  end

  @doc false
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> put_change(:is_active, true)
  end

  def providers, do: @providers

  @doc """
  Returns available regions for a given provider.
  """
  def for_provider(provider) when provider in @providers do
    # Current Hetzner regions
    case provider do
      "hetzner" ->
        [
          %{code: "eu-north-1", name: "Europe (Helsinki)"},
          %{code: "us-west-2", name: "US West (Oregon)"},
          %{code: "ap-southeast-1", name: "Asia Pacific (Singapore)"}
        ]

      # Future provider regions (commented out for now):
      # "vultr" ->
      #   [
      #     %{code: "us-east-1", name: "US East (N. Virginia)"},
      #     %{code: "eu-west-1", name: "Europe (London)"}
      #   ]
      #
      # "linode" ->
      #   [
      #     %{code: "ap-south-1", name: "Asia Pacific (Mumbai)"},
      #     %{code: "ap-southeast-2", name: "Asia Pacific (Sydney)"}
      #   ]
      #
      # "contabo" ->
      #   [
      #     %{code: "sa-east-1", name: "South America (São Paulo)"}
      #   ]

      _ ->
        []
    end
  end

  @doc """
  Returns the node name for a given region code.
  """
  def node_name(region_code) do
    :"uptrack@#{region_code}.uptrack.com"
  end

  @doc """
  Checks if a region node is available in the cluster.
  """
  def node_available?(region_code) do
    node_name(region_code) in Node.list([:this, :visible])
  end

  @doc """
  Gets the current region code from application config.
  """
  def current_region do
    Application.get_env(:uptrack, :region_code, "eu-north-1")
  end

  @doc """
  Checks if current node is the primary region.
  """
  def primary_region? do
    current_region() == "eu-north-1"
  end
end
