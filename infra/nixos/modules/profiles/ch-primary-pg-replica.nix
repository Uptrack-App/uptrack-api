# ClickHouse Primary + PostgreSQL Replica Profile
# Full database node with CH as primary and PG as replica
# Used for: Netcup Austria
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

  # ClickHouse configured as PRIMARY
  # PostgreSQL configured as Patroni REPLICA
}
