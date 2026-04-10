# Agenix secrets configuration
# This file defines all encrypted secrets for the deployment
#
# Usage:
#   1. Add node SSH host keys after initial deployment
#   2. Create/edit secrets: agenix -e <secret>.age
#   3. Re-key after adding nodes: agenix -r
#
let
  # SSH public keys for encryption
  # Your admin SSH public key (can decrypt all secrets)
  adminKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOlnOlGCkDNCBadzikbIMVBDe1jJQTDXeqZYc8e6SYIX le@le-arm64"
  ];

  # ========================================
  # NETCUP NUREMBERG NODE KEYS
  # ========================================
  # Get these by running: ssh root@<ip> cat /etc/ssh/ssh_host_ed25519_key.pub

  nbg1Key = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAd4rr7uOZTHsA305X6+x8K2vE4x5jc/crC4I2j1u+BS root@v2202511312657401393"
  ];

  nbg2Key = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILoAGQputlTNlkh5Y5EWBShCqDDh6t5OAMDgJTcvYKqs root@v2202511312657401394"
  ];

  nbg3Key = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHfdITVtibBFf7VfCDGzjxjS1mmJ3bDB7PUa82Mla2QN root@v2202511312657401395"
  ];

  nbg4Key = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDlTrRWbq1aF0nLdnh15vxmgmXk1BYhZsXnZUTRQtU9Q root@v2202511312657409490"
  ];

  # ========================================
  # ORACLE INDIA NODE KEY
  # ========================================
  # Get by running: ssh root@REMOVED_IP cat /etc/ssh/ssh_host_ed25519_key.pub

  indiaRworkerKey = [
    # ssh root@REMOVED_IP cat /etc/ssh/ssh_host_ed25519_key.pub
  ];

  # ========================================
  # ACCESS GROUPS
  # ========================================

  # All nbg nodes (Netcup Nuremberg cluster)
  nbgNodes = nbg1Key ++ nbg2Key ++ nbg3Key ++ nbg4Key;

  # All nodes that need secrets
  allNodes = adminKeys ++ nbgNodes ++ indiaRworkerKey;

  # API nodes only (nbg1 + nbg2 = coordinators with Phoenix API)
  apiNodes = adminKeys ++ nbg1Key ++ nbg2Key;

in {
  # ========================================
  # SHARED SECRETS (all nodes)
  # ========================================

  # Tailscale auth key for joining the tailnet
  # Create with: agenix -e tailscale-authkey.age
  # Content: just the auth key (tskey-auth-xxx or tskey-client-xxx)
  "tailscale-authkey.age".publicKeys = allNodes;

  # Environment variables for Uptrack app
  "uptrack-env.age".publicKeys = allNodes;

  # Environment variables for 2folk app (runs on nbg3)
  "twofolk-env.age".publicKeys = adminKeys ++ nbg3Key;

  # ========================================
  # DATABASE SECRETS (Patroni nodes: nbg1-4)
  # ========================================

  # PostgreSQL superuser password
  # Create with: agenix -e postgres-password.age
  "postgres-password.age".publicKeys = adminKeys ++ nbgNodes;

  # PostgreSQL replication password
  # Create with: agenix -e replicator-password.age
  "replicator-password.age".publicKeys = adminKeys ++ nbgNodes;

  # ========================================
  # BACKBLAZE B2 SECRETS (pgBackRest)
  # ========================================

  # B2 Application Key ID
  # Create with: agenix -e b2-key-id.age
  "b2-key-id.age".publicKeys = adminKeys ++ nbgNodes;

  # B2 Application Key (secret)
  # Create with: agenix -e b2-application-key.age
  "b2-application-key.age".publicKeys = adminKeys ++ nbgNodes;

  # Application database user password
  # Create with: agenix -e uptrack-app-password.age
  "uptrack-app-password.age".publicKeys = adminKeys ++ nbgNodes;

  # ========================================
  # API NODE SECRETS (nbg1 + nbg2)
  # ========================================

  # Cloudflare Tunnel token for public API access
  # Create with: agenix -e cloudflared-tunnel-token.age
  "cloudflared-tunnel-token.age".publicKeys = apiNodes;

  # Cloudflare API token for Let's Encrypt DNS-01 challenge (SMTP TLS cert)
  # Content: CLOUDFLARE_DNS_API_TOKEN=<token>
  "cloudflare-api-token.age".publicKeys = adminKeys ++ nbg1Key;

  # SMTP auth password for Gmail Send-as (Stalwart external submission)
  # Content: just the password string
  "smtp-password.age".publicKeys = adminKeys ++ nbg1Key;
}
