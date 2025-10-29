# Primary Node Profile
# Full stack: Uptrack app + PostgreSQL + VictoriaMetrics + HAProxy
# Used for: node-a (Hetzner primary)
{ config, pkgs, lib, ... }:

{
  imports = [
    ../services/uptrack-app.nix
    ../services/postgres.nix
    # TODO: Add VictoriaMetrics service module
    ../services/haproxy.nix
  ];
}
