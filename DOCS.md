# OpenClaw GCP — Hosting & Deployment Reference

## Goal

Run a persistent OpenClaw Gateway on a GCP Compute Engine VM using Docker, with durable state, baked-in binaries, and safe restart behavior.

Pricing varies by machine type and region; pick the smallest VM that fits your workload and scale up if you hit OOMs.

## What We're Doing

1. Create a GCP project and enable billing
2. Create a Compute Engine VM
3. Install Docker (isolated app runtime)
4. Start the OpenClaw Gateway in Docker
5. Persist `~/.openclaw` + `~/.openclaw/workspace` on the host (survives restarts/rebuilds)
6. Access the Control UI from your laptop via an SSH tunnel

The Gateway can be accessed via:
- SSH port forwarding from your laptop
- Direct port exposure if you manage firewalling and tokens yourself

This setup uses Debian on GCP Compute Engine. Ubuntu also works; map packages accordingly.

## Prerequisites

- GCP account (free tier eligible for e2-micro)
- `gcloud` CLI installed (or use Cloud Console)
- SSH access from your laptop
- ~20-30 minutes
- Docker and Docker Compose
- Model auth credentials
- Optional: WhatsApp QR, Telegram bot token, Gmail OAuth

## Machine Types

| Type | Specs | Cost | Notes |
|------|-------|------|-------|
| e2-medium | 2 vCPU, 4GB RAM | ~$25/mo | Most reliable for local Docker builds |
| e2-small | 2 vCPU, 2GB RAM | ~$12/mo | Minimum recommended for Docker build |
| e2-micro | 2 vCPU (shared), 1GB RAM | Free tier eligible | Often fails with Docker build OOM (exit 137) |

## Quick Deploy (Using This Repo's Scripts)

```bash
# 1. Edit config.env with your settings
# 2. Deploy
./deploy.sh

# 3. Check provisioning status (~5-10 min)
./status.sh

# 4. Connect via SSH tunnel
./connect.sh

# 5. Open in browser
# http://127.0.0.1:18789/
```

## Manual Step-by-Step

### 1) Install gcloud CLI

```bash
# Install from https://cloud.google.com/sdk/docs/install
gcloud init
gcloud auth login
```

### 2) Create a GCP Project

```bash
gcloud projects create my-openclaw-project --name="OpenClaw Gateway"
gcloud config set project my-openclaw-project
# Enable billing at https://console.cloud.google.com/billing
gcloud services enable compute.googleapis.com
```

### 3) Create the VM

```bash
gcloud compute instances create openclaw-gateway \
  --zone=us-central1-a \
  --machine-type=e2-small \
  --boot-disk-size=20GB \
  --image-family=debian-12 \
  --image-project=debian-cloud
```

### 4) SSH into the VM

```bash
gcloud compute ssh openclaw-gateway --zone=us-central1-a
```

SSH key propagation can take 1-2 minutes after VM creation. If connection is refused, wait and retry.

### 5) Install Docker (on the VM)

```bash
sudo apt-get update
sudo apt-get install -y git curl ca-certificates
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
exit
# SSH back in for group change to take effect
gcloud compute ssh openclaw-gateway --zone=us-central1-a
```

### 6) Clone OpenClaw

```bash
git clone https://github.com/openclaw/openclaw.git
cd openclaw
```

### 7) Create Persistent Host Directories

```bash
mkdir -p ~/.openclaw
mkdir -p ~/.openclaw/workspace
```

### 8) Configure Environment Variables

Create `.env` in the repository root:

```
OPENCLAW_IMAGE=openclaw:latest
OPENCLAW_GATEWAY_TOKEN=change-me-now
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_PORT=18789

OPENCLAW_CONFIG_DIR=/home/$USER/.openclaw
OPENCLAW_WORKSPACE_DIR=/home/$USER/.openclaw/workspace

GOG_KEYRING_PASSWORD=change-me-now
XDG_CONFIG_HOME=/home/node/.openclaw
```

Generate strong secrets with `openssl rand -hex 32`. Do not commit this file.

### 9) Docker Compose Configuration

Create/update `docker-compose.yml`:

```yaml
services:
  openclaw-gateway:
    image: ${OPENCLAW_IMAGE}
    build: .
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - HOME=/home/node
      - NODE_ENV=production
      - TERM=xterm-256color
      - OPENCLAW_GATEWAY_BIND=${OPENCLAW_GATEWAY_BIND}
      - OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD}
      - XDG_CONFIG_HOME=${XDG_CONFIG_HOME}
      - PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    volumes:
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    ports:
      - "127.0.0.1:${OPENCLAW_GATEWAY_PORT}:18789"
    command:
      [
        "node", "dist/index.js", "gateway",
        "--bind", "${OPENCLAW_GATEWAY_BIND}",
        "--port", "${OPENCLAW_GATEWAY_PORT}",
      ]
```

### 10) Bake Binaries into the Image

All external binaries required by skills must be installed at image build time — anything installed at runtime is lost on restart.

Example Dockerfile additions:

```dockerfile
FROM node:22-bookworm
RUN apt-get update && apt-get install -y socat && rm -rf /var/lib/apt/lists/*

# Example binaries
RUN curl -L https://github.com/steipete/gog/releases/latest/download/gog_Linux_x86_64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/gog
RUN curl -L https://github.com/steipete/goplaces/releases/latest/download/goplaces_Linux_x86_64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/goplaces
RUN curl -L https://github.com/steipete/wacli/releases/latest/download/wacli_Linux_x86_64.tar.gz \
  | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/wacli

WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY scripts ./scripts
RUN corepack enable
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm build
RUN pnpm ui:install
RUN pnpm ui:build
ENV NODE_ENV=production
CMD ["node","dist/index.js"]
```

If you add new skills that need additional binaries, update the Dockerfile, rebuild, and restart.

### 11) Build and Launch

```bash
docker compose build
docker compose up -d openclaw-gateway
```

If build fails with `Killed` / exit code 137, the VM is out of memory. Use e2-small minimum.

When binding to LAN, configure trusted browser origin:

```bash
docker compose run --rm openclaw-cli config set gateway.controlUi.allowedOrigins '["http://127.0.0.1:18789"]' --strict-json
```

### 12) Verify Gateway

```bash
docker compose logs -f openclaw-gateway
# Success: [gateway] listening on ws://0.0.0.0:18789
```

### 13) Access from Your Laptop

Create SSH tunnel:

```bash
gcloud compute ssh openclaw-gateway --zone=us-central1-a -- -L 18789:127.0.0.1:18789
```

Open: http://127.0.0.1:18789/

Get a tokenized dashboard link:

```bash
docker compose run --rm openclaw-cli dashboard --no-open
```

**If Control UI shows "unauthorized" or "disconnected (1008): pairing required"**, approve the browser device:

```bash
docker compose exec openclaw-gateway node dist/index.js devices list
docker compose exec openclaw-gateway node dist/index.js devices approve <requestId>
```

## Persistence Reference

| Component | Location (container) | Persistence | Notes |
|-----------|---------------------|-------------|-------|
| Gateway config | `/home/node/.openclaw/` | Host volume mount | Includes `openclaw.json`, tokens |
| Model auth profiles | `/home/node/.openclaw/` | Host volume mount | OAuth tokens, API keys |
| Skill configs | `/home/node/.openclaw/skills/` | Host volume mount | Skill-level state |
| Agent workspace | `/home/node/.openclaw/workspace/` | Host volume mount | Code and agent artifacts |
| WhatsApp session | `/home/node/.openclaw/` | Host volume mount | Preserves QR login |
| Gmail keyring | `/home/node/.openclaw/` | Host volume + password | Requires `GOG_KEYRING_PASSWORD` |
| External binaries | `/usr/local/bin/` | Docker image | Must be baked at build time |
| Docker container | Ephemeral | Restartable | Safe to destroy |

## Updates

```bash
cd ~/openclaw
git pull
docker compose build
docker compose up -d
```

## Troubleshooting

### SSH Connection Refused
SSH key propagation can take 1-2 minutes after VM creation. Wait and retry.

### OS Login Issues
```bash
gcloud compute os-login describe-profile
```
Ensure your account has Compute OS Login or Compute OS Admin Login IAM permissions.

### Out of Memory (OOM)
If Docker build fails with `Killed` and exit code 137:

```bash
gcloud compute instances stop openclaw-gateway --zone=us-central1-a
gcloud compute instances set-machine-type openclaw-gateway --zone=us-central1-a --machine-type=e2-small
gcloud compute instances start openclaw-gateway --zone=us-central1-a
```

### CLI Module Error
If `docker compose run --rm openclaw-cli <command>` fails with `Cannot find module`, use the gateway container instead:

```bash
docker compose exec openclaw-gateway node dist/index.js <command>
```

## Configuring Anthropic Authentication

The gateway needs model credentials to power the agent. Anthropic (Claude) supports two auth methods.

### Option A: API Key

Best for standard API access with usage-based billing. Supports prompt caching.

1. Create an API key at https://console.anthropic.com
2. SSH into the VM and run:

```bash
cd ~/openclaw
docker compose exec openclaw-gateway node dist/index.js onboard --anthropic-api-key "sk-ant-api..."
```

Or write it directly into the config:

```json5
// ~/.openclaw/openclaw.json
{
  env: { ANTHROPIC_API_KEY: "sk-ant-..." },
  agents: { defaults: { model: { primary: "anthropic/claude-opus-4-6" } } },
}
```

### Option B: Setup Token (OAuth / Claude Subscription)

Best for using your Claude Pro/Max subscription. Does **not** support prompt caching or the 1M context window beta.

1. On any machine with the Claude CLI installed, generate a setup token:

```bash
claude setup-token
```

2. The official way is to paste it interactively:

```bash
cd ~/openclaw
docker compose exec openclaw-gateway node dist/index.js models auth paste-token --provider anthropic
```

**However**, the `paste-token` command uses a TUI prompt that is very difficult to automate over SSH. The reliable non-interactive method is to set it directly in the config:

```bash
cd ~/openclaw
docker compose exec openclaw-gateway node dist/index.js config set env.ANTHROPIC_API_KEY "sk-ant-oat01-..."
docker compose restart openclaw-gateway
```

This works for both API keys (`sk-ant-api...`) and setup tokens (`sk-ant-oat01-...`).

### Using This Repo's Scripts

Since SSH is via IAP tunnel, run these from your laptop:

```bash
# Option A: API key (non-interactive, recommended)
gcloud compute ssh <VM_NAME> --zone=<ZONE> --tunnel-through-iap --command='
cd /home/openclaw/openclaw
sudo -u openclaw sg docker -c "docker compose exec openclaw-gateway node dist/index.js config set env.ANTHROPIC_API_KEY sk-ant-api..."
sudo -u openclaw sg docker -c "docker compose restart openclaw-gateway"
'

# Option B: Setup token (non-interactive, same config set approach)
gcloud compute ssh <VM_NAME> --zone=<ZONE> --tunnel-through-iap --command='
cd /home/openclaw/openclaw
sudo -u openclaw sg docker -c "docker compose exec openclaw-gateway node dist/index.js config set env.ANTHROPIC_API_KEY sk-ant-oat01-..."
sudo -u openclaw sg docker -c "docker compose restart openclaw-gateway"
'

# Option C: Interactive paste (requires real TTY — use ./ssh.sh)
./ssh.sh
# Then on the VM:
cd ~/openclaw
sudo -u openclaw sg docker -c "docker compose exec openclaw-gateway node dist/index.js models auth paste-token --provider anthropic"
```

### Verify Auth

```bash
gcloud compute ssh <VM_NAME> --zone=<ZONE> --tunnel-through-iap --command='
cd /home/openclaw/openclaw
sudo -u openclaw sg docker -c "docker compose exec openclaw-gateway node dist/index.js models status"
'
```

You should see a line like:
```
- anthropic effective=env:sk-ant-o...CwAA | source=env: ANTHROPIC_API_KEY
```

### Notes

- Auth is **per agent**. New agents don't inherit the main agent's keys.
- OAuth tokens can expire. Re-run `claude setup-token` and paste again if you see "OAuth token refresh failed".
- API key auth automatically enables 5-minute prompt caching (`cacheRetention: "short"`).
- See https://docs.openclaw.ai/providers/anthropic for full details.

## Known Issues & Workarounds (Learned from Setup)

### Gateway restart-loops with "Missing config" after first deploy

After provisioning completes, the gateway may restart-loop with:
```
Missing config. Run `openclaw setup` or set gateway.mode=local (or pass --allow-unconfigured).
```

Fix: run `setup` inside the container, then restart:

```bash
gcloud compute ssh <VM_NAME> --zone=<ZONE> --tunnel-through-iap --command='
cd /home/openclaw/openclaw
sudo -u openclaw sg docker -c "docker compose exec openclaw-gateway node dist/index.js setup"
sudo -u openclaw sg docker -c "docker compose restart openclaw-gateway"
'
```

### CLI service (`openclaw-cli`) fails with "Cannot find module"

The `docker compose run --rm openclaw-cli <command>` pattern from the upstream docs does not work — it fails with `Cannot find module '/app/<command>'`.

Always use the gateway container instead:

```bash
docker compose exec openclaw-gateway node dist/index.js <command>
```

### Dashboard shows "Disconnected — pairing required"

This is expected on first browser access. You need to approve the browser as a device:

```bash
# List pending requests
docker compose exec openclaw-gateway node dist/index.js devices list

# Approve the pending request
docker compose exec openclaw-gateway node dist/index.js devices approve <requestId>
```

Then refresh the browser.

### `paste-token` TUI prompt doesn't work over non-interactive SSH

The `models auth paste-token` command uses a TUI that requires a real terminal. Piping input or using `script` doesn't work reliably over IAP SSH.

Workaround: use `config set env.ANTHROPIC_API_KEY <token>` instead (works for both API keys and setup tokens). See the auth section above.

### File permissions under `.openclaw/agents/`

The `openclaw setup` command (run inside Docker as root-mapped user) can create directories under `~/.openclaw/agents/` owned by root instead of the `openclaw` user. This causes permission errors.

Fix:

```bash
sudo chown -R openclaw:openclaw /home/openclaw/.openclaw/agents/
```

### Provisioning takes ~8-10 minutes

On e2-medium, expect ~8-10 minutes for full provisioning (Docker install + image build). The Docker build (`pnpm install` + `pnpm build`) is the bottleneck. Monitor with:

```bash
./status.sh
# or watch the logs live:
./ssh.sh -- 'sudo journalctl -f -u google-startup-scripts'
```

### Getting a fresh dashboard URL

If you lose the tokenized dashboard URL:

```bash
gcloud compute ssh <VM_NAME> --zone=<ZONE> --tunnel-through-iap --command='
cd /home/openclaw/openclaw
sudo -u openclaw sg docker -c "docker compose exec openclaw-gateway node dist/index.js dashboard --no-open"
'
```

## Next Steps

- Set up messaging channels (WhatsApp, Telegram, Discord, Gmail)
- Pair local devices as nodes
- Configure the Gateway (model auth, agent defaults)
- See: https://docs.openclaw.ai/cli
