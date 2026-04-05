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

      # Disko module (for providers that need it)
      diskoModule = disko.nixosModules.disko;

      # Agenix module (for all nodes)
      agenixModule = agenix.nixosModules.default;

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

        # ========================================
        # NETCUP NUREMBERG NODES (Production)
        # ========================================

        # nbg1 - Coordinator Primary + Phoenix API
        # Note: No disko for existing systems - only used for nixos-anywhere fresh installs
        nbg1 = {
          deployment = {
            targetHost = "152.53.181.117";
            targetUser = "root";
            tags = [ "netcup" "nuremberg" "api" "coordinator" "etcd" "tailscale" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          imports = [
            agenixModule
            ./infra/nixos/regions/europe/netcup-nbg1
          ];
        };

        # nbg2 - Coordinator Standby + Phoenix API
        nbg2 = {
          deployment = {
            targetHost = "152.53.183.208";
            targetUser = "root";
            tags = [ "netcup" "nuremberg" "api" "coordinator" "etcd" "tailscale" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          imports = [
            agenixModule
            ./infra/nixos/regions/europe/netcup-nbg2
          ];
        };

        # nbg3 - Citus Worker Primary
        nbg3 = {
          deployment = {
            targetHost = "152.53.180.51";
            targetUser = "root";
            tags = [ "netcup" "nuremberg" "worker" "data" "etcd" "tailscale" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          imports = [
            agenixModule
            ./infra/nixos/regions/europe/netcup-nbg3
          ];
        };

        # nbg4 - Citus Worker Standby
        nbg4 = {
          deployment = {
            targetHost = "159.195.56.242";
            targetUser = "root";
            tags = [ "netcup" "nuremberg" "worker" "data" "tailscale" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          imports = [
            agenixModule
            ./infra/nixos/regions/europe/netcup-nbg4
          ];
        };

        # ========================================
        # CHECK WORKER NODES (Multi-region consensus)
        # ========================================

        # US - Ashburn, Virginia (RackNerd KVM)
        worker1-us-ashburn = {
          deployment = {
            targetHost = "204.152.220.248";
            targetUser = "root";
            tags = [ "worker" "racknerd" "us" "check-worker" "tailscale" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          imports = [
            ./infra/nixos/regions/americas/us-ashburn
          ];
        };

        # India - Hyderabad (Oracle Cloud ARM64)
        worker2-india = {
          deployment = {
            targetHost = "152.67.179.42";
            targetUser = "root";
            tags = [ "worker" "oracle" "asia" "india" "check-worker" "tailscale" "arm64" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          nixpkgs.system = "aarch64-linux";

          imports = [
            diskoModule
            ./infra/nixos/regions/asia/india-hyderabad/worker2-india
          ];
        };

        # ========================================
        # LEGACY NODES (Deprecated - to be removed)
        # ========================================

        # Europe - Hetzner Primary (node-a) - DEPRECATED
        hetzner-primary = {
          deployment = {
            targetHost = "91.98.89.119";
            targetUser = "root";
            tags = [ "primary" "hetzner" "europe" "app" "postgres" "victoriametrics" "haproxy" "arm64" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          nixpkgs.system = "aarch64-linux";

          imports = [
            diskoModule
            agenixModule
            ./infra/nixos/regions/europe/hetzner-primary
          ];
        };

        # Europe - Contabo Secondary (node-b)
        contabo-secondary = {
          deployment = {
            targetHost = "185.237.12.64";
            targetUser = "root";
            tags = [ "worker" "contabo" "europe" "app" "postgres" "victoriametrics" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          imports = [
            diskoModule
            agenixModule
            ./infra/nixos/regions/europe/contabo-secondary
          ];
        };

        # Europe - Contabo Tertiary (node-c)
        contabo-tertiary = {
          deployment = {
            targetHost = "147.93.146.35";
            targetUser = "root";
            tags = [ "worker" "contabo" "europe" "app" "postgres" "victoriametrics" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          imports = [
            diskoModule
            agenixModule
            ./infra/nixos/regions/europe/contabo-tertiary
          ];
        };

        # Asia - India Hyderabad Regional Worker (Oracle Free Tier ARM64)
        india-rworker = {
          deployment = {
            targetHost = "REMOVED_IP";
            targetUser = "root";
            tags = [ "worker" "oracle" "asia" "india-hyderabad" "minimal" "arm64" ];
            buildOnTarget = true;
            allowLocalDeployment = false;
          };

          nixpkgs.system = "aarch64-linux";

          imports = [
            agenixModule
            ./infra/nixos/regions/asia/india-hyderabad/india-rworker
          ];
        };
      };

      # Colmena looks for colmenaHive with makeHive
      colmenaHive = colmena.lib.makeHive self.outputs.colmena;

      # NixOS configurations for nixos-anywhere
      nixosConfigurations = {
        # ========================================
        # NETCUP NUREMBERG NODES
        # ========================================

        nbg1 = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          modules = [
            diskoModule
            agenixModule
            ./infra/nixos/regions/europe/netcup-nbg1
          ];
          specialArgs = { inherit self; };
        };

        nbg2 = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          modules = [
            diskoModule
            agenixModule
            ./infra/nixos/regions/europe/netcup-nbg2
          ];
          specialArgs = { inherit self; };
        };

        nbg3 = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          modules = [
            diskoModule
            agenixModule
            ./infra/nixos/regions/europe/netcup-nbg3
          ];
          specialArgs = { inherit self; };
        };

        nbg4 = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          modules = [
            diskoModule
            agenixModule
            ./infra/nixos/regions/europe/netcup-nbg4
          ];
          specialArgs = { inherit self; };
        };

        # ========================================
        # LEGACY NODES
        # ========================================

        hetzner-primary = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            diskoModule
            agenixModule
            ./infra/nixos/regions/europe/hetzner-primary
          ];
          specialArgs = { inherit self; };
        };

        contabo-secondary = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          modules = [
            diskoModule
            agenixModule
            ./infra/nixos/regions/europe/contabo-secondary
          ];
          specialArgs = { inherit self; };
        };

        contabo-tertiary = nixpkgs.lib.nixosSystem {
          system = linuxSystem;
          modules = [
            diskoModule
            agenixModule
            ./infra/nixos/regions/europe/contabo-tertiary
          ];
          specialArgs = { inherit self; };
        };

        india-rworker = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            agenixModule
            ./infra/nixos/regions/asia/india-hyderabad/india-rworker
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
          deploy-hetzner-primary = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "deploy-hetzner-primary" ''
              ${colmena.packages.${system}.colmena}/bin/colmena apply --on hetzner-primary
            '');
          };
          deploy-contabo-secondary = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "deploy-contabo-secondary" ''
              ${colmena.packages.${system}.colmena}/bin/colmena apply --on contabo-secondary
            '');
          };
          deploy-contabo-tertiary = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "deploy-contabo-tertiary" ''
              ${colmena.packages.${system}.colmena}/bin/colmena apply --on contabo-tertiary
            '');
          };
          deploy-india-rworker = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "deploy-india-rworker" ''
              ${colmena.packages.${system}.colmena}/bin/colmena apply --on india-rworker
            '');
          };
          install-hetzner-primary = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "install-hetzner-primary" ''
              ${nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere \
                --build-on-remote \
                --flake .#hetzner-primary \
                root@91.98.89.119
            '');
          };
          install-contabo-secondary = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "install-contabo-secondary" ''
              ${nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere \
                --build-on-remote \
                --flake .#contabo-secondary \
                root@185.237.12.64
            '');
          };
          install-contabo-tertiary = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "install-contabo-tertiary" ''
              ${nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere \
                --build-on-remote \
                --flake .#contabo-tertiary \
                root@147.93.146.35
            '');
          };
          install-india-rworker = {
            type = "app";
            program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "install-india-rworker" ''
              ${nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere \
                --build-on-remote \
                --flake .#india-rworker \
                root@REMOVED_IP
            '');
          };
        };
      in {
        x86_64-linux = mkApp "x86_64-linux";
        aarch64-darwin = mkApp "aarch64-darwin";
      };
    };
}
