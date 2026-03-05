#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

info() { echo "→ $*"; }

info "Checking VM '${VM_NAME}' in ${ZONE}…"
echo ""

VM_STATUS="$(gcloud compute instances describe "$VM_NAME" --zone="$ZONE" --format='get(status)' 2>/dev/null)" || {
  echo "ERROR: VM '${VM_NAME}' not found in zone ${ZONE}."
  exit 1
}
echo "  VM status: ${VM_STATUS}"

if [[ "$VM_STATUS" != "RUNNING" ]]; then
  echo "  VM is not running. Start it with:"
  echo "    gcloud compute instances start ${VM_NAME} --zone=${ZONE}"
  exit 0
fi

echo ""
info "Checking provisioning status…"
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --tunnel-through-iap --command='
  if [[ -f /opt/openclaw-provisioned ]]; then
    echo "  Provisioning: COMPLETE"
  else
    echo "  Provisioning: IN PROGRESS (or failed)"
    echo "  Check logs: sudo journalctl -u google-startup-scripts --no-pager -n 30"
  fi

  echo ""
  echo "  Docker:"
  if command -v docker &>/dev/null; then
    docker --version 2>/dev/null | sed "s/^/    /"
    echo ""
    echo "  Containers:"
    sudo -u openclaw docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | sed "s/^/    /" || echo "    (none running)"
    echo ""
    echo "  Gateway logs (last 5 lines):"
    cd /home/openclaw/openclaw 2>/dev/null && sudo -u openclaw docker compose logs --tail=5 openclaw-gateway 2>/dev/null | sed "s/^/    /" || echo "    (not available)"
  else
    echo "    Docker not installed yet."
  fi
' 2>/dev/null
