#!/usr/bin/env bash
set -euo pipefail

# Remove TollGate MPTCP server from a VPS
# Usage: ./scripts/teardown.sh <vps-ip>
#        ./scripts/teardown.sh -p <password> <vps-ip>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    echo "Usage: $0 [-p <ssh-password>] <vps-ip>"
    echo ""
    echo "Remove all MPTCP server components from the VPS."
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

echo "WARNING: This will remove all MPTCP server components from $VPS_IP"
echo "  - Stop and disable shadowsocks-libev"
echo "  - Stop and disable glorytun"
echo "  - Remove NAT rules"
echo "  - Remove /opt/tollgate/mptcp data"
echo ""
read -p "Are you sure? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Build SSH args
SSH_ARGS=(-o StrictHostKeyChecking=no)
SSH_CMD="ssh"
if [ -n "$SSH_PASS" ]; then
    if ! command -v sshpass &>/dev/null; then
        echo "Error: sshpass not found."
        exit 1
    fi
    export SSHPASS="$SSH_PASS"
    SSH_CMD="sshpass -e ssh"
fi

echo "Tearing down MPTCP server on $VPS_IP..."

$SSH_CMD "${SSH_ARGS[@]}" root@"$VPS_IP" bash -s <<'REMOTE'
set -euo pipefail

echo "Stopping services..."
systemctl stop shadowsocks-libev-server@config 2>/dev/null || true
systemctl disable shadowsocks-libev-server@config 2>/dev/null || true
systemctl stop glorytun-server 2>/dev/null || true
systemctl disable glorytun-server 2>/dev/null || true
systemctl stop mptcp-limits 2>/dev/null || true
systemctl disable mptcp-limits 2>/dev/null || true

echo "Removing systemd overrides..."
rm -rf /etc/systemd/system/shadowsocks-libev-server@config.service.d
rm -f /etc/systemd/system/glorytun-server.service
rm -f /etc/systemd/system/mptcp-limits.service
systemctl daemon-reload

echo "Removing data..."
rm -rf /opt/tollgate/mptcp

echo "Removing MPTCP sysctl config..."
rm -f /etc/sysctl.d/90-mptcp.conf
sysctl --system >/dev/null 2>&1

echo "Done. MPTCP server components removed."
REMOTE

echo ""
echo "Teardown complete."
