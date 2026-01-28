# pgBackRest - PostgreSQL Backup & Restore
# Provides disaster recovery backups to Backblaze B2 with:
#   - Full backups (weekly)
#   - Differential backups (daily)
#   - Continuous WAL archiving
#   - Point-in-time recovery (PITR)
#
# Each Patroni cluster has its own stanza:
#   - "coordinator" stanza: nbg1/nbg2 cluster
#   - "worker" stanza: nbg3/nbg4 cluster
{ config, pkgs, lib, ... }:

let
  nodeName = config.networking.hostName;

  # Nodes that run pgBackRest (all Patroni nodes)
  coordinatorNodes = [ "nbg1" "nbg2" ];
  workerNodes = [ "nbg3" "nbg4" ];
  allNodes = coordinatorNodes ++ workerNodes;

  isBackupNode = builtins.elem nodeName allNodes;
  isCoordinator = builtins.elem nodeName coordinatorNodes;

  # Stanza name matches Patroni cluster scope
  stanzaName = if isCoordinator then "coordinator" else "worker";

  # Backblaze B2 endpoint (us-west-004)
  b2Endpoint = "s3.us-west-004.backblazeb2.com";
  b2Bucket = "uptrack-pgbackrest";
  b2Region = "us-west-004";

in lib.mkIf isBackupNode {
  # Declare agenix secrets for B2 credentials
  age.secrets = {
    b2-key-id = {
      file = ../../secrets/b2-key-id.age;
      owner = "patroni";
      group = "patroni";
      mode = "0400";
    };
    b2-application-key = {
      file = ../../secrets/b2-application-key.age;
      owner = "patroni";
      group = "patroni";
      mode = "0400";
    };
  };

  # Install pgBackRest
  environment.systemPackages = [ pkgs.pgbackrest ];

  # pgBackRest configuration
  environment.etc."pgbackrest/pgbackrest.conf" = {
    mode = "0640";
    user = "patroni";
    group = "patroni";
    text = ''
      [global]
      # Repository configuration (Backblaze B2 via S3 API)
      repo1-type=s3
      repo1-s3-endpoint=${b2Endpoint}
      repo1-s3-bucket=${b2Bucket}
      repo1-s3-region=${b2Region}
      repo1-path=/${stanzaName}
      repo1-retention-full=4
      repo1-retention-diff=7
      repo1-cipher-type=aes-256-cbc

      # Compression
      compress-type=zst
      compress-level=3

      # Parallel processing
      process-max=2

      # Logging
      log-level-console=info
      log-level-file=detail
      log-path=/var/log/pgbackrest

      # PostgreSQL connection (via Patroni socket)
      pg1-socket-path=/run/patroni
      pg1-user=postgres

      [${stanzaName}]
      pg1-path=/var/lib/postgresql/17
    '';
  };

  # Script to load B2 credentials and run pgbackrest
  environment.etc."pgbackrest/run-pgbackrest.sh" = {
    mode = "0750";
    text = ''
      #!/bin/bash
      export PGBACKREST_REPO1_S3_KEY=$(cat ${config.age.secrets.b2-key-id.path})
      export PGBACKREST_REPO1_S3_KEY_SECRET=$(cat ${config.age.secrets.b2-application-key.path})
      export PGBACKREST_REPO1_CIPHER_PASS=$(cat ${config.age.secrets.b2-application-key.path} | sha256sum | cut -d' ' -f1)
      exec pgbackrest "$@"
    '';
  };

  # Create log directory
  systemd.tmpfiles.rules = [
    "d /var/log/pgbackrest 0750 patroni patroni -"
  ];

  # Systemd service for full backup (weekly)
  systemd.services.pgbackrest-full = {
    description = "pgBackRest Full Backup";
    after = [ "patroni.service" ];
    requires = [ "patroni.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "patroni";
      Group = "patroni";
      ExecStart = "/etc/pgbackrest/run-pgbackrest.sh --stanza=${stanzaName} backup --type=full";
      TimeoutStartSec = "2h";
    };
  };

  # Systemd timer for full backup (Sunday 2am UTC)
  systemd.timers.pgbackrest-full = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 02:00:00 UTC";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };

  # Systemd service for differential backup (daily)
  systemd.services.pgbackrest-diff = {
    description = "pgBackRest Differential Backup";
    after = [ "patroni.service" ];
    requires = [ "patroni.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "patroni";
      Group = "patroni";
      ExecStart = "/etc/pgbackrest/run-pgbackrest.sh --stanza=${stanzaName} backup --type=diff";
      TimeoutStartSec = "1h";
    };
  };

  # Systemd timer for differential backup (daily 3am UTC, except Sunday)
  systemd.timers.pgbackrest-diff = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon..Sat *-*-* 03:00:00 UTC";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
