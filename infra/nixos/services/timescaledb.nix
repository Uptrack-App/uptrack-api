# TimescaleDB Extension Configuration
{ config, pkgs, lib, ... }:

{
  # TimescaleDB is included in PostgreSQL 16 package
  services.postgresql = {
    extraPlugins = with pkgs.postgresql_16.pkgs; [
      timescaledb
    ];
    
    settings = {
      shared_preload_libraries = "timescaledb";
    };
  };
}
