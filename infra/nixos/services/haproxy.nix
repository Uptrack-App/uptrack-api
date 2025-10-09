# HAProxy Load Balancer Configuration
{ config, pkgs, lib, ... }:

{
  services.haproxy = {
    enable = true;
    
    config = ''
      defaults
        log     global
        mode    http
        option  httplog
        option  dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000

      # Frontend for HTTP
      frontend http_frontend
        bind *:80
        mode http
        default_backend uptrack_backend

      # Backend for Uptrack Application
      backend uptrack_backend
        mode http
        balance roundrobin
        option httpchk GET /
        server uptrack1 127.0.0.1:4000 check
    '';
  };

  # Open HTTP/HTTPS ports
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
