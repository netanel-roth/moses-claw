#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

echo "This will permanently delete VM '${VM_NAME}' in zone ${ZONE}."
echo "All data on the VM (including ~/.openclaw) will be lost."
echo ""
read -rp "Are you sure? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

echo "→ Deleting VM '${VM_NAME}'…"
gcloud compute instances delete "$VM_NAME" \
  --zone="$ZONE" \
  --quiet

echo ""
read -rp "Also remove the service account and firewall rule? [y/N] " cleanup
if [[ "$cleanup" =~ ^[Yy]$ ]]; then
  SA_EMAIL="openclaw-vm@${GCP_PROJECT}.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null 2>&1; then
    echo "→ Deleting service account…"
    gcloud iam service-accounts delete "$SA_EMAIL" --quiet
  fi

  FW_RULE="allow-ssh-iap-openclaw"
  if gcloud compute firewall-rules describe "$FW_RULE" &>/dev/null 2>&1; then
    echo "→ Deleting IAP firewall rule…"
    gcloud compute firewall-rules delete "$FW_RULE" --quiet
  fi
fi

SECRETS_FILE="${SCRIPT_DIR}/.secrets.${VM_NAME}"
if [[ -f "$SECRETS_FILE" ]]; then
  rm -f "$SECRETS_FILE"
  echo "→ Removed local secrets file."
fi

echo "→ Done."
