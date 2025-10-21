{
  description = "Uptrack - Multi-region uptime monitoring with NixOS deployment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # For deploying with Colmena
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For automated remote NixOS installation
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For secrets management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, colmena, nixos-anywhere, disko, agenix, ... }:
    let
      # System for NixOS servers
      linuxSystem = "x86_64-linux";

      # Common modules shared across all machines
      commonModules = [
        disko.nixosModules.disko
        agenix.nixosModules.default
        ./infra/nixos/common.nix
      ];

    in {
      # Colmena deployment configuration
      colmena = {
        meta = {
          nixpkgs = import nixpkgs {
            system = linuxSystem;
          };

          # Global specialArgs for all nodes
          specialArgs = {
            inherit self;
          };
        };

        # Node A - Primary (Hetzner ARM64)
        node-a = {
          deployment = {
            targetHost = "91.98.89.119";
            targetUser = "root";
            tags = [ "primary" "hetzner" "app" "postgres" "arm64" ];
            buildOnTarget = true;  # Build on server to save bandwidth
            allowLocalDeployment = false;
          };

          # Override nixpkgs for ARM64
          nixpkgs.system = "aarch64-linux";

          imports = commonModules ++ [
            ./infra/nixos/node-a.nix
            ./infra/nixos/services/uptrack-app.nix
            ./infra/nixos/services/postgres.nix
            ./infra/nixos/services/clickhouse.nix
            ./infra/nixos/services/haproxy.nix
          ];
        };

        # Node B - Secondary (Contabo)
        node-b = {
          deployment = {
            targetHost = "185.237.12.64";
            targetUser = "root";
            tags = [ "secondary" "contabo" "app" "postgres" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          imports = commonModules ++ [
            ./infra/nixos/node-b.nix
            ./infra/nixos/services/uptrack-app.nix
            ./infra/nixos/services/postgres.nix
            ./infra/nixos/services/clickhouse.nix
          ];
        };

        # Node C - Tertiary (Contabo)
        node-c = {
          deployment = {
            targetHost = "147.93.146.35";
            targetUser = "root";
            tags = [ "tertiary" "contabo" "app" "clickhouse" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          imports = commonModules ++ [
            ./infra/nixos/node-c.nix
            ./infra/nixos/services/uptrack-app.nix
            ./infra/nixos/services/postgres.nix
            ./infra/nixos/services/clickhouse.nix
          ];
        };

        # Node India Strong - Minimal config (Oracle Free Tier ARM64)
        node-india-strong = {
          deployment = {
            targetHost = "152.67.179.42";
            targetUser = "le";
            tags = [ "oracle" "app" "arm64" "minimal" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          # Override nixpkgs for ARM64
          nixpkgs.system = "aarch64-linux";

          imports = commonModules ++ [
            ./infra/nixos/node-india-strong-minimal.nix
            # NOT using service modules - deploy app as release instead
          ];
        };

        # Node India Weak - App-only + etcd (Oracle Free Tier ARM64)
        node-india-weak = {
          deployment = {
            targetHost = "INDIA_WEAK_IP";  # Update with actual IP
            targetUser = "root";
            tags = [ "app" "etcd" "oracle" "arm64" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          # Override nixpkgs for ARM64
          nixpkgs.system = "aarch64-linux";

          imports = commonModules ++ [
            ./infra/nixos/node-india-weak.nix
            ./infra/nixos/services/uptrack-app.nix
          ];
        };
      };

      # Colmena looks for colmenaHive with makeHive
      colmenaHive = colmena.lib.makeHive self.outputs.colmena;

      # NixOS configurations for nixos-anywhere
      nixosConfigurations = {
        node-a = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";  # Hetzner ARM64 server
          modules = commonModules ++ [
            ./infra/nixos/node-a.nix
            ./infra/nixos/services/uptrack-app.nix
            ./infra/nixos/services/postgres.nix
            ./infra/nixos/services/clickhouse.nix
            ./infra/nixos/services/haproxy.nix
          ];
          specialArgs = { inherit self; };
        };

        node-b = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          modules = commonModules ++ [
            ./infra/nixos/node-b.nix
            ./infra/nixos/services/uptrack-app.nix
            ./infra/nixos/services/postgres.nix
            ./infra/nixos/services/clickhouse.nix
          ];
          specialArgs = { inherit self; };
        };

        node-c = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          modules = commonModules ++ [
            ./infra/nixos/node-c.nix
            ./infra/nixos/services/uptrack-app.nix
            ./infra/nixos/services/postgres.nix
            ./infra/nixos/services/clickhouse.nix
          ];
          specialArgs = { inherit self; };
        };

        node-india-strong = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";  # Oracle Free ARM64
          modules = commonModules ++ [
            ./infra/nixos/node-india-strong-minimal.nix
            ./infra/nixos/services/idle-prevention.nix  # Generate load to prevent Oracle reclamation
            # NOT using service modules - deploy app as release instead
            # NO postgres, clickhouse, uptrack-app modules (caused boot failures)
          ];
          specialArgs = { inherit self; };
        };

        node-india-weak = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";  # Oracle Free ARM64
          modules = commonModules ++ [
            ./infra/nixos/node-india-weak.nix
            ./infra/nixos/services/uptrack-app.nix
          ];
          specialArgs = { inherit self; };
        };
      };

      # Development shell with deployment tools
      devShells = {
        x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
          buildInputs = with nixpkgs.legacyPackages.x86_64-linux; [
            colmena.packages.x86_64-linux.colmena
            nixos-anywhere.packages.x86_64-linux.default
            agenix.packages.x86_64-linux.default
            git rsync openssh
          ];
          shellHook = ''
            echo "🚀 Uptrack NixOS Deployment Environment"
            echo ""
            echo "Available commands:"
            echo "  colmena apply          - Deploy to all nodes"
            echo "  colmena apply --on node-a  - Deploy to single node"
            echo "  colmena apply --on @app    - Deploy to all app nodes"
            echo "  colmena build          - Build configs without deploying"
            echo ""
          '';
        };

        aarch64-darwin.default = nixpkgs.legacyPackages.aarch64-darwin.mkShell {
          buildInputs = with nixpkgs.legacyPackages.aarch64-darwin; [
            colmena.packages.aarch64-darwin.colmena
            nixos-anywhere.packages.aarch64-darwin.default
            agenix.packages.aarch64-darwin.default
            git rsync openssh
          ];
          shellHook = ''
            echo "🚀 Uptrack NixOS Deployment Environment"
            echo ""
            echo "Available commands:"
            echo "  colmena apply          - Deploy to all nodes"
            echo "  colmena apply --on node-a  - Deploy to single node"
            echo "  colmena apply --on @app    - Deploy to all app nodes"
            echo "  colmena build          - Build configs without deploying"
            echo ""
          '';
        };
      };

      # Convenience apps for deployment
      apps = let
        mkApp = system: {
          deploy-all = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "deploy-all" ''
              ${colmena.packages.${system}.colmena}/bin/colmena apply
            '');
          };
          deploy-node-a = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "deploy-node-a" ''
              ${colmena.packages.${system}.colmena}/bin/colmena apply --on node-a
            '');
          };
          deploy-node-b = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "deploy-node-b" ''
              ${colmena.packages.${system}.colmena}/bin/colmena apply --on node-b
            '');
          };
          deploy-node-c = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "deploy-node-c" ''
              ${colmena.packages.${system}.colmena}/bin/colmena apply --on node-c
            '');
          };
          install-node-a = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "install-node-a" ''
              ${nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere \
                --build-on-remote \
                --flake .#node-a \
                root@91.98.89.119
            '');
          };
          install-node-b = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "install-node-b" ''
              ${nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere \
                --build-on-remote \
                --flake .#node-b \
                root@185.237.12.64
            '');
          };
          install-node-c = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "install-node-c" ''
              ${nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere \
                --build-on-remote \
                --flake .#node-c \
                root@147.93.146.35
            '');
          };
          deploy-node-india-strong = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "deploy-node-india-strong" ''
              ${colmena.packages.${system}.colmena}/bin/colmena apply --on node-india-strong
            '');
          };
          deploy-node-india-weak = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "deploy-node-india-weak" ''
              ${colmena.packages.${system}.colmena}/bin/colmena apply --on node-india-weak
            '');
          };
          install-node-india-strong = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "install-node-india-strong" ''
              ${nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere \
                --build-on-remote \
                --flake .#node-india-strong \
                root@144.24.133.171
            '');
          };
          install-node-india-weak = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "install-node-india-weak" ''
              ${nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere \
                --build-on-remote \
                --flake .#node-india-weak \
                root@INDIA_WEAK_IP
            '');
          };
        };
      in {
        x86_64-linux = mkApp "x86_64-linux";
        aarch64-darwin = mkApp "aarch64-darwin";
      };
    };
}
