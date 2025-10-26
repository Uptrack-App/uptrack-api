# Primary Node Profile
# Full stack: Uptrack app + PostgreSQL + ClickHouse + HAProxy
# Used for: node-a (Hetzner primary)
{ config, pkgs, lib, ... }:

{
  imports = [
    ../services/uptrack-app.nix
    ../services/postgres.nix
    ../services/clickhouse.nix
    ../services/haproxy.nix
  ];
}
