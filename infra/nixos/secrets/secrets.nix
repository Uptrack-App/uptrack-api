# Agenix secrets configuration
# This file defines all encrypted secrets for the deployment
let
  # SSH public keys for encryption
  # Your admin SSH public key
  adminKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com"
  ];

  # Server SSH host keys (add after initial deployment)
  # Get these by running: ssh root@<ip> cat /etc/ssh/ssh_host_ed25519_key.pub
  nodeAKey = [
    # Add after installing Node A: ssh root@91.98.89.119 cat /etc/ssh/ssh_host_ed25519_key.pub
  ];

  nodeBKey = [
    # Add after installing Node B: ssh root@185.237.12.64 cat /etc/ssh/ssh_host_ed25519_key.pub
  ];

  nodeCKey = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID4Cq2eVhte57p1hanUNMT2C98YW2pOABIb/zny+iPns root@uptrack-node-c"
  ];

  # Who can decrypt secrets for each node
  nodeAUsers = adminKeys ++ nodeAKey;
  nodeBUsers = adminKeys ++ nodeBKey;
  nodeCUsers = adminKeys ++ nodeCKey;
  allUsers = adminKeys ++ nodeAKey ++ nodeBKey ++ nodeCKey;

in {
  # Single secret file with all environment variables
  # Each node can decrypt its own secrets
  "uptrack-env.age".publicKeys = allUsers;
}
