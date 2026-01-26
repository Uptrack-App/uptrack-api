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
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com"
  ];

  # ========================================
  # NETCUP NUREMBERG NODE KEYS
  # ========================================
  # Get these by running: ssh root@<ip> cat /etc/ssh/ssh_host_ed25519_key.pub

  nbg1Key = [
    # ssh root@152.53.181.117 cat /etc/ssh/ssh_host_ed25519_key.pub
  ];

  nbg2Key = [
    # ssh root@152.53.183.208 cat /etc/ssh/ssh_host_ed25519_key.pub
  ];

  nbg3Key = [
    # ssh root@152.53.180.51 cat /etc/ssh/ssh_host_ed25519_key.pub
  ];

  nbg4Key = [
    # ssh root@159.195.56.242 cat /etc/ssh/ssh_host_ed25519_key.pub
  ];

  # ========================================
  # LEGACY NODE KEYS (to be removed)
  # ========================================
  nodeAKey = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEun58BHKtRxbZ0OXMD/gdsL5gfnuiDI+dCw5KgKCT1V root@uptrack-node-a"
  ];

  nodeCKey = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID4Cq2eVhte57p1hanUNMT2C98YW2pOABIb/zny+iPns root@uptrack-node-c"
  ];

  # ========================================
  # ACCESS GROUPS
  # ========================================

  # All nbg nodes (Netcup Nuremberg cluster)
  nbgNodes = nbg1Key ++ nbg2Key ++ nbg3Key ++ nbg4Key;

  # All nodes that need secrets
  allNodes = adminKeys ++ nbgNodes ++ nodeAKey ++ nodeCKey;

  # API nodes only (nbg1 + nbg4 = coordinators with Phoenix API)
  apiNodes = adminKeys ++ nbg1Key ++ nbg4Key;

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

  # ========================================
  # DATABASE SECRETS
  # ========================================

  # PostgreSQL passwords (for Patroni/Citus)
  # "postgres-passwords.age".publicKeys = allNodes;

  # pgBackRest encryption key for B2 backups
  # "pgbackrest-cipher.age".publicKeys = allNodes;

  # ========================================
  # API NODE SECRETS (nbg1, nbg4 only)
  # ========================================

  # Secrets only needed by Phoenix API nodes
  # "api-secrets.age".publicKeys = apiNodes;
}
