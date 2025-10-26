# App-Only Profile
# Application node with no databases
# Used for: OVH Canada, regional expansion nodes
{ config, pkgs, lib, ... }:

{
  imports = [
    ../services/uptrack-app.nix
    ../services/etcd.nix
  ];

  # No PostgreSQL, No ClickHouse
  # Just Uptrack app + etcd for cluster coordination
}
