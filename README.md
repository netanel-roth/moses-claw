# OpenClaw GCP — One-click VM Deployment

Deploy a persistent OpenClaw Gateway on a GCP Compute Engine VM with a single command.

## Prerequisites

- GCP account with billing enabled
- `gcloud` CLI installed and authenticated (`gcloud auth login`)
- A GCP project (or the deploy script will use the one in `config.env`)

## Quick Start

```bash
# 1. Edit config.env with your GCP project and preferences
vim config.env

# 2. Deploy (creates VM + provisions everything automatically)
./deploy.sh

# 3. Wait ~5-10 minutes for provisioning, then check status
./status.sh

# 4. Connect via SSH tunnel
./connect.sh
# Open http://127.0.0.1:18789/ in your browser
```

## Scripts

| Script | What it does |
|---|---|
| `deploy.sh` | Creates a GCP VM and provisions OpenClaw via startup script |
| `connect.sh` | Opens an SSH tunnel so you can access the Gateway locally |
| `status.sh` | Checks VM status, provisioning state, and gateway health |
| `update.sh` | Pulls latest OpenClaw and rebuilds on the VM |
| `ssh.sh` | SSH into the VM (shortcut for `gcloud compute ssh`) |
| `destroy.sh` | Deletes the VM and optionally cleans up SA + firewall rules |

## Configuration

All settings live in `config.env`. Edit it once before your first deploy.

Key settings:
- **GCP_PROJECT** — your GCP project ID (must have billing enabled)
- **VM_NAME** — name for the Compute Engine VM
- **MACHINE_TYPE** — `e2-small` ($12/mo) recommended; `e2-medium` ($25/mo) for reliable builds
- **SSH_ACCESS** — `iap` (recommended) or `open`
- **BUDGET_AMOUNT** — monthly dollar budget alert (set to `""` to skip)
- **GATEWAY_TOKEN / GOG_KEYRING_PASSWORD** — auto-generated if left empty

## Security Model

The deploy script applies these hardening measures automatically:

### Dedicated service account (least privilege)
The VM runs under `openclaw-vm@<project>.iam.gserviceaccount.com` with **no GCP API permissions** (only `logging.write` scope). The default Compute Engine service account (which has Editor role) is never used.

### IAP-tunneled SSH (no public SSH)
When `SSH_ACCESS=iap` (the default), the deploy script:
- Creates a firewall rule allowing SSH **only from Google's IAP range** (`35.235.240.0/20`)
- Tags the VM so only this rule applies
- Removes the default `allow-ssh-from-anywhere` rule

This means SSH only works through `gcloud compute ssh`, which authenticates via your Google identity. Direct SSH from the internet is blocked entirely.

### OS Login
SSH keys are managed via IAM (OS Login) instead of project-wide metadata SSH keys. Only users with the `Compute OS Login` IAM role on the project can SSH into the VM.

### Loopback-only gateway
The gateway port binds to `127.0.0.1` inside the VM — it's never exposed to the network. Access is only through the SSH tunnel (`./connect.sh`).

### Billing budget alert
If `BUDGET_AMOUNT` is set, a Cloud Billing budget is created with alerts at 50%, 90%, and 100% of the monthly budget.

### Secrets handling
- Secrets are auto-generated with `openssl rand -hex 32`
- Saved locally to `.secrets.<vm-name>` with `chmod 600`
- Git-ignored via `.gitignore`

## Deploying Multiple Instances

Change `VM_NAME` in `config.env` (or override it) and run `deploy.sh` again:

```bash
VM_NAME=openclaw-staging ./deploy.sh
VM_NAME=openclaw-staging ./connect.sh
```

## What Happens on Deploy

1. Enables required GCP APIs (Compute, IAP, optionally Billing Budgets)
2. Creates a dedicated service account with no GCP permissions
3. Sets up IAP SSH firewall rules (blocks direct internet SSH)
4. Creates a Compute Engine VM with OS Login enabled
5. The VM's startup script automatically:
   - Installs Docker
   - Clones the OpenClaw repo
   - Generates a Dockerfile with your chosen binaries baked in
   - Writes `.env` and `docker-compose.yml`
   - Builds the Docker image and starts the gateway
6. Creates a billing budget alert
7. Saves secrets locally (git-ignored, `chmod 600`)

## Troubleshooting

**Build fails with exit code 137 (OOM)**
Change `MACHINE_TYPE` to `e2-medium` in `config.env`, destroy and redeploy.

**SSH connection refused after deploy**
SSH key propagation takes 1-2 minutes. Wait and retry.

**IAP SSH permission denied**
Your Google account needs the `IAP-Secured Tunnel User` role and `Compute OS Login` role on the project:
```bash
gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --member="user:you@example.com" \
  --role="roles/iap.tunnelResourceAccessor"

gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --member="user:you@example.com" \
  --role="roles/compute.osLogin"
```

**Gateway shows "unauthorized"**
Approve the browser device:
```bash
./ssh.sh -- 'cd ~/openclaw && docker compose run --rm openclaw-cli devices list'
./ssh.sh -- 'cd ~/openclaw && docker compose run --rm openclaw-cli devices approve <requestId>'
```
