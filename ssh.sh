#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

IAP_FLAG=()
if [[ "${SSH_ACCESS:-iap}" == "iap" ]]; then
  IAP_FLAG=(--tunnel-through-iap)
fi

gcloud compute ssh "$VM_NAME" --zone="$ZONE" "${IAP_FLAG[@]}" -- "$@"
