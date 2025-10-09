# PostgreSQL Service Configuration
{ config, pkgs, lib, ... }:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    
    # Listen on all interfaces
    enableTCPIP = true;
    
    settings = {
      max_connections = 100;
      shared_buffers = "256MB";
      effective_cache_size = "1GB";
      work_mem = "16MB";
      maintenance_work_mem = "64MB";
    };

    # Authentication
    authentication = pkgs.lib.mkOverride 10 ''
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      local   all             all                                     trust
      host    all             all             127.0.0.1/32            md5
      host    all             all             ::1/128                 md5
    '';
  };

  # Ensure PostgreSQL is started before other services
  systemd.services.postgresql.wantedBy = [ "multi-user.target" ];
}
