# Minimal Node Profile
# PostgreSQL only (app deployed as release)
# Used for: Oracle Cloud Free Tier ARM64 instances
# Note: ClickHouse too resource-intensive for free tier
{ config, pkgs, lib, ... }:

{
  imports = [
    ../services/postgres.nix
  ];

  # Note: Uptrack app is deployed as a release, not via NixOS module
  # This keeps the NixOS config minimal and allows app updates without full system rebuilds
}
