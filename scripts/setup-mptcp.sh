#!/usr/bin/env bash
set -euo pipefail

# Deploy TollGate MPTCP server to a VPS
# Usage: ./scripts/setup-mptcp.sh <vps-ip>
#        ./scripts/setup-mptcp.sh -p <password> <vps-ip>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    echo "Usage: $0 [-p <ssh-password>] <vps-ip>"
    echo ""
    echo "Deploy the TollGate MPTCP aggregation server to a VPS."
    echo ""
    echo "Options:"
    echo "  -p <password>   SSH password for the VPS (or set TG_SSH_PASS env var)"
    echo ""
    echo "Examples:"
    echo "  $0 203.0.113.10                    # SSH key auth"
    echo "  $0 -p mypassword 203.0.113.10      # Password auth"
    echo "  TG_SSH_PASS=mypass $0 203.0.113.10  # Password via env var"
}

# Parse SSH password flag
SSH_PASS="${TG_SSH_PASS:-}"
while getopts ":p:" opt; do
    case $opt in
        p) SSH_PASS="$OPTARG" ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

VPS_IP="$1"

# Check dependencies
if ! command -v ansible-playbook &>/dev/null; then
    echo "Error: ansible-playbook not found. Install with: pip install ansible"
    exit 1
fi

# Build ansible command
ANSIBLE_CMD=(ansible-playbook -i "$PROJECT_DIR/inventory/hosts.yml"
    "$PROJECT_DIR/playbook.yml"
    --tags setup
    -e "vps_ip=$VPS_IP")

if [ -n "$SSH_PASS" ]; then
    if ! command -v sshpass &>/dev/null; then
        echo "Error: sshpass not found. Install with: brew install sshpass (macOS) or apt install sshpass (Linux)"
        exit 1
    fi
    ANSIBLE_CMD+=("--ask-pass")
    export ANSIBLE_SSH_PASS="$SSH_PASS"
    # Use sshpass for non-interactive password auth
    export SSHPASS="$SSH_PASS"
    ANSIBLE_CMD=(sshpass -e "${ANSIBLE_CMD[@]}")
fi

echo "Deploying TollGate MPTCP server to $VPS_IP..."
echo ""

cd "$PROJECT_DIR"
"${ANSIBLE_CMD[@]}"

echo ""
echo "MPTCP server deployed successfully!"
echo "Server config saved on VPS at: /opt/tollgate/mptcp/server-config.txt"
echo ""
echo "To verify: ./scripts/verify-mptcp.sh $VPS_IP"
