
⏺ You already have a solid NixOS setup! Let me simplify what you have and what you need:

  Your Current Structure (You Already Have This!)

  infra/nixos/
  ├── common/           # Shared configs per provider
  │   ├── base.nix      # ✅ All nodes inherit this
  │   ├── hostkey.nix   # ✅ HostKey-specific (zone-1-a,b,c)
  │   ├── netcup.nix    # ✅ Netcup-specific
  │   └── oracle.nix    # ✅ Oracle-specific
  │
  ├── disko/            # Disk partitioning per provider
  │   ├── hostkey-bios.nix   # ✅ For HostKey nodes
  │   └── oracle-free-tier.nix
  │
  ├── modules/
  │   ├── profiles/     # Role-based configs
  │   │   ├── worker.nix     # App + PG + VM
  │   │   └── primary.nix    # Full stack
  │   └── services/     # Individual services (TODO)
  │
  └── regions/          # Per-node configs
      ├── europe/zone-1-a/   # ✅ HostKey Italy
      ├── europe/zone-1-b/   # ✅ HostKey Italy
      └── asia/india-*/      # ✅ Oracle India

  NixOS Simplified

  Think of it as layers:

  ┌─────────────────────────────────────────────┐
  │  Node Config (regions/europe/zone-1-a/)     │  ← Specific: hostname, IP
  ├─────────────────────────────────────────────┤
  │  Provider Config (common/hostkey.nix)       │  ← Provider: boot, network
  ├─────────────────────────────────────────────┤
  │  Profile (modules/profiles/worker.nix)      │  ← Role: services to run
  ├─────────────────────────────────────────────┤
  │  Base (common/base.nix)                     │  ← Universal: SSH, packages
  └─────────────────────────────────────────────┘

  What You Need to Add

  1. Service Modules (the TODO parts)

  infra/nixos/modules/services/
  ├── tailscale.nix      # ✅ You have this
  ├── postgresql.nix     # TODO: PostgreSQL + Patroni
  ├── etcd.nix           # TODO: etcd cluster
  ├── vmstorage.nix      # TODO: VictoriaMetrics storage
  ├── vminsert.nix       # TODO: VictoriaMetrics insert
  ├── vmselect.nix       # TODO: VictoriaMetrics select
  └── uptrack-app.nix    # TODO: Phoenix app

  2. Example: vmstorage.nix (Simple Version)

  # infra/nixos/modules/services/vmstorage.nix
  { config, pkgs, lib, ... }:

  {
    options.services.uptrack.vmstorage = {
      enable = lib.mkEnableOption "VictoriaMetrics storage";
      retentionPeriod = lib.mkOption {
        type = lib.types.str;
        default = "15M";  # 15 months
      };
    };

    config = lib.mkIf config.services.uptrack.vmstorage.enable {
      # Download vmstorage binary
      environment.systemPackages = [ pkgs.victoriametrics ];

      # Create systemd service
      systemd.services.vmstorage = {
        description = "VictoriaMetrics Storage";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        serviceConfig = {
          ExecStart = ''
            ${pkgs.victoriametrics}/bin/vmstorage \
              -storageDataPath=/var/lib/vmstorage \
              -retentionPeriod=${config.services.uptrack.vmstorage.retentionPeriod} \
              -httpListenAddr=:8482 \
              -vminsertAddr=:8400 \
              -vmselectAddr=:8401
          '';
          Restart = "always";
          StateDirectory = "vmstorage";
        };
      };

      # Open ports on Tailscale only
      networking.firewall.interfaces."tailscale0" = {
        allowedTCPPorts = [ 8400 8401 8482 ];
      };
    };
  }

  3. Using It in a Node

  # infra/nixos/regions/europe/zone-1-c/default.nix (nbg-3)
  { config, pkgs, lib, ... }:

  {
    imports = [
      ../../../common/base.nix
      ../../../common/hostkey.nix
      ../../../modules/services/tailscale.nix
      ../../../modules/services/vmstorage.nix  # Add this
    ];

    networking.hostName = "uptrack-zone-1-c";

    # Enable vmstorage on this node
    services.uptrack.vmstorage.enable = true;

    # ... rest of config
  }

  Deployment Workflow

  # 1. Enter dev shell (has colmena, nixos-anywhere)
  nix develop

  # 2. Build without deploying (check for errors)
  colmena build --on zone-1-a

  # 3. Deploy to one node
  colmena apply --on zone-1-a

  # 4. Deploy to all zone-1 nodes
  colmena apply --on @zone-1

  # 5. Fresh install (wipes and installs NixOS)
  nix run .#install-zone-1-a

  Your 3 Questions Answered

  | Question                   | Answer                                           |
  |----------------------------|--------------------------------------------------|
  | NixOS for Netcup           | Use common/netcup.nix + ARM64 disko              |
  | NixOS for HostHatch        | Create common/hosthatch.nix (similar to hostkey) |
  | NixOS for regional workers | Use modules/profiles/worker.nix with vmagent     |

  Suggested Next Step

  Start with one service module to learn the pattern:

  # Create the vmstorage module
  touch infra/nixos/modules/services/vmstorage.nix

  Want me to create complete service modules for:
  1. vmstorage.nix
  2. vminsert.nix
  3. vmselect.nix

  These are simpler than PostgreSQL/Patroni and good for learning NixOS patterns.