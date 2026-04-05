# Rebuild from Scratch

If the VM dies, the GCP project is deleted, or you need to rebuild everything — this is your recovery guide.

## Prerequisites

- `gcloud` CLI installed and authenticated (`gcloud auth login`)
- `gh` CLI authenticated (`gh auth login`)
- Access to the 3 GitHub repos (`mosesclaw-gcp`, `moses_claw_workspace`, `ami_support_workspace`)
- Original secret values (backed up elsewhere — Secret Manager will need to be recreated if the project is gone)

## Step 1: GCP Project

```bash
# Create project (if needed)
gcloud projects create moses-claw --name="moses-claw"

# Link billing
gcloud billing projects link moses-claw --billing-account=<BILLING_ACCOUNT_ID>

# Enable APIs
gcloud services enable compute.googleapis.com iap.googleapis.com secretmanager.googleapis.com --project=moses-claw
```

## Step 2: Secret Manager

Recreate all 6 secrets (see `../gcp/secrets-catalog.md`):

```bash
for name in GROQ_API_KEY GEMINI_API_KEY TAVILY_API_KEY TELEGRAM_BOT_TOKEN OPENCLAW_GATEWAY_TOKEN GOG_KEYRING_PASSWORD; do
  gcloud secrets create $name --project=moses-claw --replication-policy=automatic
  echo -n "<VALUE>" | gcloud secrets versions add $name --project=moses-claw --data-file=-
done
```

## Step 3: Deploy VM

```bash
cd mosesclaw-gcp
# Review config.env (project, zone, machine type)
./deploy.sh
```

Wait ~8-10 min for initial provisioning.

## Step 4: Grant Secret Manager access

```bash
gcloud projects add-iam-policy-binding moses-claw \
  --member="serviceAccount:openclaw-vm@moses-claw.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# VM needs cloud-platform scope
gcloud compute instances stop openclaw-gateway --zone=europe-west1-b --project=moses-claw
gcloud compute instances set-service-account openclaw-gateway \
  --zone=europe-west1-b --project=moses-claw \
  --service-account=openclaw-vm@moses-claw.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/cloud-platform
gcloud compute instances start openclaw-gateway --zone=europe-west1-b --project=moses-claw
```

## Step 5: Install custom scripts on VM

```bash
./ssh.sh

# On VM:
sudo tee /usr/local/bin/openclaw-secret-resolver > /dev/null < <(cat path/to/infra/scripts/openclaw-secret-resolver)
sudo chmod +x /usr/local/bin/openclaw-secret-resolver

sudo tee /usr/local/bin/openclaw-fetch-secrets.sh > /dev/null < <(cat path/to/infra/scripts/openclaw-fetch-secrets.sh)
sudo chmod +x /usr/local/bin/openclaw-fetch-secrets.sh

# Run fetcher to populate .env.secrets
sudo /usr/local/bin/openclaw-fetch-secrets.sh
```

## Step 6: Apply VM customizations

Copy these from `infra/config/` to the VM:
- `Dockerfile` → `/home/openclaw/openclaw/Dockerfile`
- `Dockerfile.sandbox` → `/home/openclaw/openclaw/Dockerfile.sandbox`
- `docker-compose.yml` → `/home/openclaw/openclaw/docker-compose.yml`
- `openclaw.json` → `/home/openclaw/.openclaw/openclaw.json`

Then:

```bash
# Rebuild sandbox image
cd /home/openclaw/openclaw
sudo -u openclaw sg docker -c "bash scripts/sandbox-setup.sh"

# Rebuild main image (has Docker CLI baked in)
sudo -u openclaw sg docker -c "docker compose build openclaw-gateway"

# Start gateway
sudo -u openclaw sg docker -c "docker compose up -d openclaw-gateway"
```

## Step 7: SSH deploy keys

Regenerate deploy keys (private keys can't be recovered):

```bash
sudo -u openclaw ssh-keygen -t ed25519 -f /home/openclaw/.ssh/github_deploy -N "" -C "moses-claw-deploy-key"
sudo -u openclaw ssh-keygen -t ed25519 -f /home/openclaw/.ssh/github_deploy_ami -N "" -C "ami-support-deploy-key"
```

Add public keys to GitHub:
- `github_deploy.pub` → `netanel-roth/moses_claw_workspace` deploy keys (write access)
- `github_deploy_ami.pub` → `netanel-roth/ami_support_workspace` deploy keys (write access)

## Step 8: Clone workspaces into VM

```bash
sudo -u openclaw bash -c "
  cd /home/openclaw/.openclaw
  rm -rf workspace workspace-ami-support
  GIT_SSH_COMMAND='ssh -i /home/openclaw/.ssh/github_deploy' git clone git@github.com:netanel-roth/moses_claw_workspace.git workspace
  GIT_SSH_COMMAND='ssh -i /home/openclaw/.ssh/github_deploy_ami' git clone git@github.com:netanel-roth/ami_support_workspace.git workspace-ami-support
"
```

## Step 9: Install cron jobs

Copy `infra/cron/openclaw-user-crontab.txt` content to the VM:

```bash
sudo -u openclaw crontab path/to/infra/cron/openclaw-user-crontab.txt
```

## Step 10: OpenAI Codex OAuth

```bash
cd /home/openclaw/openclaw
sudo -u openclaw sg docker -c "docker compose exec -it openclaw-gateway node dist/index.js models auth login --provider openai-codex"
```

## Step 11: Telegram pairing

```bash
# Restart gateway to pick up Telegram bot token
sudo -u openclaw sg docker -c "docker compose restart openclaw-gateway"
```

## Step 12: WhatsApp pairing

```bash
# WhatsApp will need re-pairing (QR scan)
cd /home/openclaw/openclaw
sudo -u openclaw sg docker -c "docker compose exec -it openclaw-gateway node dist/index.js channels login --channel whatsapp"
```

Scan the QR code with your phone.

## Step 13: Test

- Send a mentioned message in a WhatsApp group → Moses should reply
- Send a mentioned message in the AMI test group → AMI should reply
- Check both workspaces are auto-syncing to GitHub via cron

Estimated rebuild time: ~30-45 minutes (most of it is waiting for Docker builds).
