# Worker Node Profile
# App + PostgreSQL + VictoriaMetrics (no HAProxy)
# Used for: node-b, node-c (Contabo workers)
{ config, pkgs, lib, ... }:

{
  imports = [
    ../services/uptrack-app.nix
    ../services/postgres.nix
    # TODO: Add VictoriaMetrics service module
  ];
}
