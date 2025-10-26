# Worker Node Profile
# App + PostgreSQL + ClickHouse (no HAProxy)
# Used for: node-b, node-c (Contabo workers)
{ config, pkgs, lib, ... }:

{
  imports = [
    ../services/uptrack-app.nix
    ../services/postgres.nix
    ../services/clickhouse.nix
  ];
}
