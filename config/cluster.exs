# Erlang Cluster Configuration for Multi-Region Monitoring
#
# Current setup: Hetzner-only deployment
# Future: Multi-provider expansion (Vultr, Linode, etc.)

import Config

# Get region configuration from environment
region_code = System.get_env("REGION_CODE") || "eu-north-1"
node_env = System.get_env("NODE_ENV") || "prod"

# Configure node name based on region
config :uptrack,
  region_code: region_code,
  node_name: :"uptrack@#{region_code}.uptrack.com"

# Cluster topology configuration
config :libcluster,
  topologies: [
    uptrack_cluster: [
      strategy: Cluster.Strategy.Epmd,
      config: [
        # Current Hetzner regions
        hosts: [
          :"uptrack@eu-north-1.uptrack.com",    # Main (Helsinki) - CAX11
          :"uptrack@us-west-2.uptrack.com",     # US West - CPX11
          :"uptrack@ap-southeast-1.uptrack.com" # Asia (Singapore) - CPX11
        ]

        # Future multi-provider expansion:
        # :"uptrack@us-east-1.vultr.com",       # Vultr (New Jersey)
        # :"uptrack@sa-east-1.contabo.com",     # Contabo (São Paulo)
        # :"uptrack@ap-south-1.linode.com",     # Linode (Mumbai)
        # :"uptrack@ap-southeast-2.linode.com", # Linode (Sydney)
        # :"uptrack@eu-west-1.vultr.com"        # Vultr (London)
      ]
    ]
  ]

# Region-specific configurations
case region_code do
  "eu-north-1" ->
    # Main node (Helsinki) - ARM64 CAX11
    config :uptrack,
      role: :primary,
      database_writer: true,
      web_server: true,
      scheduler: true,
      check_worker: true

  "us-west-2" ->
    # US West worker - AMD CPX11
    config :uptrack,
      role: :worker,
      database_writer: false,
      web_server: false,
      scheduler: false,
      check_worker: true

  "ap-southeast-1" ->
    # Asia worker - AMD CPX11
    config :uptrack,
      role: :worker,
      database_writer: false,
      web_server: false,
      scheduler: false,
      check_worker: true

  # Future multi-provider regions:
  # "us-east-1" ->
  #   # Vultr US East
  #   config :uptrack,
  #     role: :worker,
  #     provider: :vultr,
  #     check_worker: true
  #
  # "sa-east-1" ->
  #   # Contabo Brazil
  #   config :uptrack,
  #     role: :worker,
  #     provider: :contabo,
  #     check_worker: true
  #
  # "ap-south-1" ->
  #   # Linode India
  #   config :uptrack,
  #     role: :worker,
  #     provider: :linode,
  #     check_worker: true

  _ ->
    # Default fallback
    config :uptrack,
      role: :primary,
      database_writer: true,
      web_server: true,
      scheduler: true,
      check_worker: true
end

# Network configuration for cross-region communication
config :uptrack, Uptrack.Cluster,
  # Hetzner private networking (10.0.0.0/8)
  allowed_ips: [
    "10.0.0.0/8",     # Hetzner private network
    "172.31.0.0/16"   # Hetzner cloud private network
  ],

  # Future: Multi-provider VPN mesh
  # wireguard_config: [
  #   interface: "wg0",
  #   peers: [
  #     # Vultr peers
  #     %{public_key: "...", endpoint: "vultr-us-east.uptrack.com:51820"},
  #     # Linode peers
  #     %{public_key: "...", endpoint: "linode-ap-south.uptrack.com:51820"},
  #     # Contabo peers
  #     %{public_key: "...", endpoint: "contabo-sa-east.uptrack.com:51820"}
  #   ]
  # ],

  # Security
  cookie: System.get_env("ERLANG_COOKIE") || "uptrack_secure_cookie_change_in_prod",
  epmd_port: 4369,
  dist_port_range: {9000, 9100}

# Region availability mapping for UI
config :uptrack, Uptrack.Regions,
  available_regions: [
    # Current Hetzner regions
    %{code: "eu-north-1", name: "Europe (Helsinki)", provider: :hetzner, active: true},
    %{code: "us-west-2", name: "US West (Oregon)", provider: :hetzner, active: true},
    %{code: "ap-southeast-1", name: "Asia Pacific (Singapore)", provider: :hetzner, active: true}

    # Future regions (commented out):
    # %{code: "us-east-1", name: "US East (N. Virginia)", provider: :vultr, active: false},
    # %{code: "sa-east-1", name: "South America (São Paulo)", provider: :contabo, active: false},
    # %{code: "ap-south-1", name: "Asia Pacific (Mumbai)", provider: :linode, active: false},
    # %{code: "ap-southeast-2", name: "Asia Pacific (Sydney)", provider: :linode, active: false},
    # %{code: "eu-west-1", name: "Europe (London)", provider: :vultr, active: false}
  ]