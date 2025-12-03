#!/usr/bin/env bash
# Install Tailscale on Debian/Ubuntu nodes
# Usage: ./install-tailscale-debian.sh <hostname> <tailscale-auth-key>
#
# Hostnames: eu-a, eu-b, eu-c, india-w
# Auth key: REMOVED_TAILSCALE_AUTH_KEY

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -ne 2 ]; then
  echo -e "${RED}Error: Missing arguments${NC}"
  echo "Usage: $0 <hostname> <tailscale-auth-key>"
  echo ""
  echo "Examples:"
  echo "  $0 eu-a REMOVED_TAILSCALE_AUTH_KEY"
  echo "  $0 eu-b REMOVED_TAILSCALE_AUTH_KEY"
  echo "  $0 india-w REMOVED_TAILSCALE_AUTH_KEY"
  exit 1
fi

HOSTNAME="$1"
AUTHKEY="$2"

# Validate hostname
case "$HOSTNAME" in
  eu-a|eu-b|eu-c|india-w)
    echo -e "${GREEN}✓ Valid hostname: $HOSTNAME${NC}"
    ;;
  *)
    echo -e "${RED}Error: Invalid hostname '$HOSTNAME'${NC}"
    echo "Valid hostnames: eu-a, eu-b, eu-c, india-w"
    exit 1
    ;;
esac

echo -e "${YELLOW}Installing Tailscale on $HOSTNAME...${NC}"

# Detect OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
  VERSION=$VERSION_ID
else
  echo -e "${RED}Error: Cannot detect OS${NC}"
  exit 1
fi

echo -e "${GREEN}Detected OS: $OS $VERSION${NC}"

# Install Tailscale
case "$OS" in
  ubuntu|debian)
    echo -e "${YELLOW}Installing Tailscale for Debian/Ubuntu...${NC}"

    # Add Tailscale's package repository
    if [ ! -f /usr/share/keyrings/tailscale-archive-keyring.gpg ]; then
      echo "Adding Tailscale repository..."
      curl -fsSL https://pkgs.tailscale.com/stable/$OS/$VERSION_CODENAME.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
      curl -fsSL https://pkgs.tailscale.com/stable/$OS/$VERSION_CODENAME.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
    fi

    # Update and install
    sudo apt-get update -qq
    sudo apt-get install -y tailscale

    echo -e "${GREEN}✓ Tailscale installed${NC}"
    ;;

  *)
    echo -e "${RED}Error: Unsupported OS: $OS${NC}"
    echo "This script supports Debian/Ubuntu. For other OS, install manually:"
    echo "https://tailscale.com/download"
    exit 1
    ;;
esac

# Start Tailscale daemon
echo -e "${YELLOW}Starting Tailscale daemon...${NC}"
sudo systemctl enable --now tailscaled

# Wait for daemon to be ready
sleep 2

# Connect to Tailscale
echo -e "${YELLOW}Connecting to Tailscale network...${NC}"
sudo tailscale up \
  --hostname="$HOSTNAME" \
  --authkey="$AUTHKEY" \
  --accept-routes \
  --advertise-tags="tag:infrastructure"

# Check status
echo -e "${GREEN}✓ Tailscale connected${NC}"
echo ""
echo -e "${GREEN}=== Tailscale Status ===${NC}"
sudo tailscale status

echo ""
echo -e "${GREEN}=== Tailscale IP ===${NC}"
TAILSCALE_IP=$(sudo tailscale ip -4)
echo "IPv4: $TAILSCALE_IP"

echo ""
echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Go to Tailscale admin console: https://login.tailscale.com/admin/machines"
echo "2. Find machine '$HOSTNAME' (current IP: $TAILSCALE_IP)"
echo "3. Edit machine settings → 'Edit IP address'"
echo "4. Set static IP according to plan:"
echo "   - eu-a: 100.64.1.1"
echo "   - eu-b: 100.64.1.2"
echo "   - eu-c: 100.64.1.3"
echo "   - india-w: 100.64.1.11"
echo ""
echo "5. Test connectivity from another node:"
echo "   ping $TAILSCALE_IP"
echo "   ssh root@$TAILSCALE_IP  # (after static IP assigned)"
