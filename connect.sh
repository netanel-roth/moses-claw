#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

echo "→ Opening SSH tunnel to ${VM_NAME} (port ${GATEWAY_PORT})…"
echo "  Open http://127.0.0.1:${GATEWAY_PORT}/ in your browser."
echo "  Press Ctrl+C to disconnect."
echo ""

gcloud compute ssh "$VM_NAME" \
  --zone="$ZONE" \
  --tunnel-through-iap \
  -- -L "${GATEWAY_PORT}:127.0.0.1:${GATEWAY_PORT}" -N
