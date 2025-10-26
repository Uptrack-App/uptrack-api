# PostgreSQL Primary + ClickHouse Replica Profile
# Full database node with PG as primary and CH as replica
# Used for: Netcup Germany
{ config, pkgs, lib, ... }:

{
  imports = [
    ../services/uptrack-app.nix
    ../services/postgres.nix
    ../services/clickhouse.nix
    ../services/haproxy.nix
    ../services/patroni.nix
    ../services/etcd.nix
  ];

  # PostgreSQL configured as Patroni PRIMARY
  # ClickHouse configured as REPLICA
}
