# GCP IAM Bindings

Project: `moses-claw`

## Service Accounts

### `openclaw-vm@moses-claw.iam.gserviceaccount.com`
- **Purpose:** VM runtime identity
- **Created by:** `deploy.sh`
- **Roles:**
  - `roles/secretmanager.secretAccessor` — read secrets from Secret Manager

### VM Access Scopes
- `https://www.googleapis.com/auth/logging.write`
- `https://www.googleapis.com/auth/cloud-platform` (needed for Secret Manager)

## User Access

### `mosiek2805@gmail.com` / `moshekeva@gmail.com`
- **Role on project:** `roles/owner` (project creator)

## Firewall Rules

| Rule | Purpose | Source | Target |
|---|---|---|---|
| `allow-ssh-iap-openclaw` | SSH via IAP tunnel only | `35.235.240.0/20` (Google IAP range) | Tag: `openclaw-iap-ssh` |

No public SSH, no public HTTP/HTTPS, no public ports at all.
