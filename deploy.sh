#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "→ $*"; }

generate_secret() { openssl rand -hex 32; }

# ── Pre-flight checks ───────────────────────────
command -v gcloud >/dev/null 2>&1 || die "gcloud CLI not found. Install from https://cloud.google.com/sdk/docs/install"

[[ -n "$GCP_PROJECT" ]] || die "GCP_PROJECT is not set in config.env"
[[ -n "$VM_NAME" ]]     || die "VM_NAME is not set in config.env"

if [[ -z "$GATEWAY_TOKEN" ]]; then
  GATEWAY_TOKEN="$(generate_secret)"
  info "Auto-generated GATEWAY_TOKEN"
fi
if [[ -z "$GOG_KEYRING_PASSWORD" ]]; then
  GOG_KEYRING_PASSWORD="$(generate_secret)"
  info "Auto-generated GOG_KEYRING_PASSWORD"
fi

# ── Set project ──────────────────────────────────
info "Setting GCP project to ${GCP_PROJECT}…"
gcloud config set project "$GCP_PROJECT" --quiet

# ── Enable required APIs ─────────────────────────
info "Enabling required APIs…"
APIS="compute.googleapis.com iap.googleapis.com"
if [[ -n "${BUDGET_AMOUNT:-}" ]]; then
  APIS="$APIS billingbudgets.googleapis.com"
fi
gcloud services enable $APIS --quiet

# ── Check if VM already exists ───────────────────
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" &>/dev/null; then
  die "VM '${VM_NAME}' already exists in zone ${ZONE}. Use destroy.sh first, or choose a different VM_NAME."
fi

# ── Create a dedicated service account (least privilege) ──
SA_NAME="openclaw-vm"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
  info "Creating dedicated service account '${SA_NAME}'…"
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="OpenClaw VM (no GCP API access)" \
    --quiet
else
  info "Service account '${SA_NAME}' already exists."
fi

# ── IAP SSH firewall rule ────────────────────────
SSH_ACCESS="${SSH_ACCESS:-iap}"
FW_RULE_NAME="allow-ssh-iap-openclaw"

if [[ "$SSH_ACCESS" == "iap" ]]; then
  if ! gcloud compute firewall-rules describe "$FW_RULE_NAME" &>/dev/null 2>&1; then
    info "Creating IAP SSH firewall rule…"
    gcloud compute firewall-rules create "$FW_RULE_NAME" \
      --network=default \
      --allow=tcp:22 \
      --source-ranges=35.235.240.0/20 \
      --target-tags=openclaw-iap-ssh \
      --description="Allow SSH only from IAP tunnel (Google's IAP IP range)" \
      --quiet
  fi
fi

# ── Build startup script from template ───────────
info "Preparing startup script…"
STARTUP_SCRIPT="$(cat "${SCRIPT_DIR}/startup-script.sh")"

CLEAN_URLS="$(echo "$EXTRA_BINARY_URLS" | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//')"

STARTUP_SCRIPT="${STARTUP_SCRIPT//__OPENCLAW_REPO__/$OPENCLAW_REPO}"
STARTUP_SCRIPT="${STARTUP_SCRIPT//__OPENCLAW_BRANCH__/$OPENCLAW_BRANCH}"
STARTUP_SCRIPT="${STARTUP_SCRIPT//__GATEWAY_PORT__/$GATEWAY_PORT}"
STARTUP_SCRIPT="${STARTUP_SCRIPT//__GATEWAY_TOKEN__/$GATEWAY_TOKEN}"
STARTUP_SCRIPT="${STARTUP_SCRIPT//__GOG_KEYRING_PASSWORD__/$GOG_KEYRING_PASSWORD}"
STARTUP_SCRIPT="${STARTUP_SCRIPT//__EXTRA_BINARY_URLS__/$CLEAN_URLS}"

TMPFILE="$(mktemp)"
echo "$STARTUP_SCRIPT" > "$TMPFILE"

# ── Create VM ────────────────────────────────────
VM_TAGS="openclaw"
if [[ "$SSH_ACCESS" == "iap" ]]; then
  VM_TAGS="openclaw,openclaw-iap-ssh"
fi

info "Creating VM '${VM_NAME}' (${MACHINE_TYPE}) in ${ZONE}…"
gcloud compute instances create "$VM_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --boot-disk-size="$BOOT_DISK_SIZE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --metadata-from-file=startup-script="$TMPFILE" \
  --metadata=enable-oslogin=TRUE \
  --service-account="$SA_EMAIL" \
  --scopes=https://www.googleapis.com/auth/logging.write \
  --tags="$VM_TAGS" \
  --quiet

rm -f "$TMPFILE"

# ── Block direct SSH if using IAP ────────────────
if [[ "$SSH_ACCESS" == "iap" ]]; then
  DEFAULT_SSH_RULE="default-allow-ssh"
  if gcloud compute firewall-rules describe "$DEFAULT_SSH_RULE" &>/dev/null 2>&1; then
    info "Removing default allow-ssh-from-anywhere firewall rule…"
    gcloud compute firewall-rules delete "$DEFAULT_SSH_RULE" --quiet 2>/dev/null || true
  fi

  info "SSH is locked down to IAP tunnel only."
  info "  'gcloud compute ssh' works automatically through IAP."
  info "  Direct SSH from the internet is blocked."
fi

# ── Billing budget alert ─────────────────────────
if [[ -n "${BUDGET_AMOUNT:-}" ]]; then
  BILLING_ACCOUNT="$(gcloud billing projects describe "$GCP_PROJECT" --format='value(billingAccountName)' 2>/dev/null | sed 's|billingAccounts/||')"
  if [[ -n "$BILLING_ACCOUNT" ]]; then
    info "Creating billing budget alert (\$${BUDGET_AMOUNT}/month)…"
    BUDGET_EXISTS="$(gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --format='value(displayName)' 2>/dev/null | grep -c "openclaw-${VM_NAME}" || true)"
    if [[ "$BUDGET_EXISTS" -eq 0 ]]; then
      gcloud billing budgets create \
        --billing-account="$BILLING_ACCOUNT" \
        --display-name="openclaw-${VM_NAME}" \
        --budget-amount="${BUDGET_AMOUNT}USD" \
        --threshold-rule=percent=0.5 \
        --threshold-rule=percent=0.9 \
        --threshold-rule=percent=1.0 \
        --quiet 2>/dev/null || info "  (budget creation skipped — may need Billing Admin role)"
    else
      info "  Budget alert already exists."
    fi
  else
    info "  Could not determine billing account — skipping budget alert."
  fi
fi

# ── Save secrets locally ─────────────────────────
SECRETS_FILE="${SCRIPT_DIR}/.secrets.${VM_NAME}"
cat > "$SECRETS_FILE" <<EOF
# Auto-generated secrets for VM: ${VM_NAME}
# Created: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
GATEWAY_TOKEN=${GATEWAY_TOKEN}
GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD}
EOF
chmod 600 "$SECRETS_FILE"

info ""
info "VM created. Provisioning runs in the background (~5-10 min)."
info ""
info "Security summary:"
info "  Service account: ${SA_EMAIL} (no GCP API permissions)"
info "  OS Login: enabled (SSH keys managed via IAM)"
info "  SSH access: ${SSH_ACCESS}"
[[ -n "${BUDGET_AMOUNT:-}" ]] && info "  Budget alert: \$${BUDGET_AMOUNT}/month"
info "  Gateway port: loopback only (127.0.0.1:${GATEWAY_PORT})"
info "  Secrets: ${SECRETS_FILE}"
info ""
info "Next steps:"
info "  Monitor provisioning: ./ssh.sh -- 'sudo journalctl -f -u google-startup-scripts'"
info "  Check status:         ./status.sh"
info "  Connect:              ./connect.sh"
