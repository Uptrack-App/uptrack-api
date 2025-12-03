#!/usr/bin/env bash
# Setup SSH keys on all Hostkey nodes
# Password: +9m5YWR1iN

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Setting Up SSH Keys on Hostkey Nodes ===${NC}"
echo ""
echo "Passwords (enter when prompted):"
echo "  eu-a (REMOVED_IP): sEGsqcEi4L"
echo "  eu-b (REMOVED_IP): W3ZuN9bg6m"
echo "  eu-c (REMOVED_IP): jA-gMAiBOm"
echo ""
echo "Note: These are temporary passwords. Change them after SSH keys are setup!"
echo ""

# Check if ssh-copy-id exists
if ! command -v ssh-copy-id &> /dev/null; then
    echo -e "${YELLOW}Installing ssh-copy-id...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install ssh-copy-id
    else
        echo "Please install ssh-copy-id manually"
        exit 1
    fi
fi

# EU nodes with their passwords
NODES=(
    "eu-a:REMOVED_IP:sEGsqcEi4L"
    "eu-b:REMOVED_IP:W3ZuN9bg6m"
    "eu-c:REMOVED_IP:jA-gMAiBOm"
)

for node in "${NODES[@]}"; do
    IFS=':' read -r NAME IP PASSWORD <<< "$node"

    echo -e "${YELLOW}=== Setting up SSH key for $NAME ($IP) ===${NC}"
    echo "Enter password when prompted: $PASSWORD"
    echo ""

    ssh-copy-id -o StrictHostKeyChecking=no root@$IP

    echo ""
    echo -e "${GREEN}✓ $NAME key copied${NC}"
    echo ""
done

echo -e "${GREEN}=== Testing SSH Keys ===${NC}"
echo ""

for node in "${NODES[@]}"; do
    IFS=':' read -r NAME IP PASSWORD <<< "$node"

    echo -n "Testing $NAME... "
    if ssh -o ConnectTimeout=5 root@$IP "echo 'OK'" &>/dev/null; then
        echo -e "${GREEN}✓ Works without password!${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
done

echo ""
echo -e "${GREEN}✓✓✓ SSH keys setup complete! ✓✓✓${NC}"
echo ""
echo "Now run: ./scripts/deploy-tailscale-all.sh"
