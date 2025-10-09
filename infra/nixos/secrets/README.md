# Secrets Management with Agenix

This directory contains encrypted secrets for Uptrack deployment using [agenix](https://github.com/ryantm/agenix).

## Setup

1. **Initial Setup** (before first deployment):
   ```bash
   # Copy example and fill in real values
   cp uptrack-env.example uptrack-env
   vim uptrack-env  # Add real secrets

   # Generate secrets if needed
   ../../../nixos-deploy.sh generate-keys
   ```

2. **After Installing NixOS** on a server:
   ```bash
   # Get the server's SSH host key
   ssh root@<server-ip> cat /etc/ssh/ssh_host_ed25519_key.pub
   
   # Add it to secrets.nix in the appropriate nodeXKey list
   vim secrets.nix
   ```

3. **Encrypt Secrets**:
   ```bash
   # Encrypt the uptrack-env file
   nix develop --command agenix -e uptrack-env.age
   
   # Or use the helper script
   ../../../nixos-deploy.sh rekey
   ```

## Files

- `secrets.nix` - Defines who can decrypt which secrets (public keys)
- `uptrack-env.example` - Template for environment variables
- `uptrack-env` - **NEVER COMMIT** - Your actual secrets
- `uptrack-env.age` - Encrypted secrets (safe to commit)

## Workflow

### Initial Deployment

1. Copy and fill in secrets:
   ```bash
   cp uptrack-env.example uptrack-env
   # Edit uptrack-env with real values
   ```

2. Install NixOS on a node (this creates SSH host keys):
   ```bash
   ./nixos-deploy.sh install-node-c
   ```

3. Get the server's SSH host key and add to secrets.nix:
   ```bash
   ssh root@147.93.146.35 cat /etc/ssh/ssh_host_ed25519_key.pub
   # Add output to nodeCKey in secrets.nix
   ```

4. Encrypt secrets:
   ```bash
   nix develop --command agenix -e uptrack-env.age
   ```

5. Deploy:
   ```bash
   ./nixos-deploy.sh deploy-node-c
   ```

### Updating Secrets

1. Edit the encrypted file:
   ```bash
   nix develop --command agenix -e uptrack-env.age
   ```

2. Deploy changes:
   ```bash
   ./nixos-deploy.sh deploy-node-c
   ```

### Adding a New Server

1. Install NixOS on the server
2. Get its SSH host key
3. Add the key to `secrets.nix`
4. Re-encrypt all secrets:
   ```bash
   ./nixos-deploy.sh rekey
   ```

## Security

- Only encrypted `.age` files are committed to git
- Unencrypted secrets are in `.gitignore`
- Each server can only decrypt secrets encrypted with its SSH host key
- Your admin SSH key allows you to decrypt all secrets locally

## Troubleshooting

**"No identities found" error:**
- Make sure your SSH key (`~/.ssh/id_ed25519`) matches the key in `secrets.nix`
- The key must be an ed25519 key

**Server can't decrypt secrets:**
- Make sure the server's SSH host key is in `secrets.nix`
- Re-run `./nixos-deploy.sh rekey` after adding the key
- Redeploy: `./nixos-deploy.sh deploy-node-x`
