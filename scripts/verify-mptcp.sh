#!/usr/bin/env bash
set -euo pipefail

# Verify TollGate MPTCP server is healthy
# Usage: ./scripts/verify-mptcp.sh <vps-ip>
#        ./scripts/verify-mptcp.sh -p <password> <vps-ip>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    echo "Usage: $0 [-p <ssh-password>] <vps-ip>"
    echo ""
    echo "Run health checks on the deployed MPTCP server."
    echo ""
    echo "Options:"
    echo "  -p <password>   SSH password for the VPS (or set TG_SSH_PASS env var)"
}

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

if ! command -v ansible-playbook &>/dev/null; then
    echo "Error: ansible-playbook not found."
    exit 1
fi

ANSIBLE_CMD=(ansible-playbook -i "$PROJECT_DIR/inventory/hosts.yml"
    "$PROJECT_DIR/playbook.yml"
    --tags verify
    -e "vps_ip=$VPS_IP")

if [ -n "$SSH_PASS" ]; then
    if ! command -v sshpass &>/dev/null; then
        echo "Error: sshpass not found."
        exit 1
    fi
    export SSHPASS="$SSH_PASS"
    ANSIBLE_CMD=(sshpass -e "${ANSIBLE_CMD[@]}")
fi

echo "Running health checks on MPTCP server at $VPS_IP..."
echo ""

cd "$PROJECT_DIR"
"${ANSIBLE_CMD[@]}"
