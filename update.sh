#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

echo "→ Updating OpenClaw on VM '${VM_NAME}'…"

gcloud compute ssh "$VM_NAME" --zone="$ZONE" --tunnel-through-iap --command='
  set -euo pipefail
  cd /home/openclaw/openclaw
  echo "  Pulling latest…"
  sudo -u openclaw git pull
  echo "  Rebuilding Docker image…"
  sudo -u openclaw sg docker -c "docker compose build" 2>&1 | tail -5
  echo "  Restarting gateway…"
  sudo -u openclaw sg docker -c "docker compose up -d openclaw-gateway"
  echo "  Done. Waiting for startup…"
  sleep 10
  echo "  Last 5 log lines:"
  sudo -u openclaw sg docker -c "docker logs openclaw-openclaw-gateway-1 --tail=5" 2>&1 || true
'
