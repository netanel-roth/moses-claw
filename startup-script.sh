#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

OPENCLAW_REPO="__OPENCLAW_REPO__"
OPENCLAW_BRANCH="__OPENCLAW_BRANCH__"
GATEWAY_PORT="__GATEWAY_PORT__"
GATEWAY_TOKEN="__GATEWAY_TOKEN__"
GOG_KEYRING_PASSWORD="__GOG_KEYRING_PASSWORD__"
EXTRA_BINARY_URLS="__EXTRA_BINARY_URLS__"

OC_USER="openclaw"
HOME_DIR="/home/${OC_USER}"
REPO_DIR="${HOME_DIR}/openclaw"
MARKER="/opt/openclaw-provisioned"

log() { echo "[openclaw-setup] $(date '+%H:%M:%S') $*"; }

# ── Already provisioned → pull latest and rebuild ─
if [[ -f "$MARKER" ]]; then
  log "Already provisioned — checking for updates…"
  cd "$REPO_DIR"

  BEFORE="$(sudo -u "$OC_USER" git rev-parse HEAD)"
  sudo -u "$OC_USER" git pull --ff-only || { log "Git pull failed — skipping update."; exit 0; }
  AFTER="$(sudo -u "$OC_USER" git rev-parse HEAD)"

  if [[ "$BEFORE" == "$AFTER" ]]; then
    log "Already on latest ($BEFORE). Starting gateway…"
    sudo -u "$OC_USER" sg docker -c "docker compose up -d openclaw-gateway"
    exit 0
  fi

  log "Updated $BEFORE → $AFTER. Rebuilding…"
  sudo -u "$OC_USER" sg docker -c "docker compose build" 2>&1 | tail -5
  sudo -u "$OC_USER" sg docker -c "docker compose up -d openclaw-gateway"
  log "Update complete."
  exit 0
fi

# ── First-time provisioning ──────────────────────

# 1. Create dedicated system user
if ! id "$OC_USER" &>/dev/null; then
  log "Creating system user '${OC_USER}'…"
  useradd -m -s /bin/bash "$OC_USER"
fi

# 2. Install Docker
log "Installing system packages…"
apt-get update -qq
apt-get install -y -qq git curl ca-certificates jq cloud-guest-utils > /dev/null

log "Installing Docker…"
curl -fsSL https://get.docker.com | sh
usermod -aG docker "$OC_USER"

# 3. Clone repo
if [[ ! -d "$REPO_DIR" ]]; then
  log "Cloning OpenClaw (branch: ${OPENCLAW_BRANCH})…"
  sudo -u "$OC_USER" git clone --branch "$OPENCLAW_BRANCH" "$OPENCLAW_REPO" "$REPO_DIR"
fi

# 4. Persistent directories
log "Creating persistent directories…"
sudo -u "$OC_USER" mkdir -p "${HOME_DIR}/.openclaw"
sudo -u "$OC_USER" mkdir -p "${HOME_DIR}/.openclaw/workspace"

# 5. Generate Dockerfile with baked binaries
log "Generating Dockerfile…"
BINARY_LINES=""
for url in $EXTRA_BINARY_URLS; do
  [[ -z "$url" ]] && continue
  BINARY_LINES="${BINARY_LINES}
RUN curl -fsSL ${url} | tar -xz -C /usr/local/bin && chmod +x /usr/local/bin/*"
done

cat > "${REPO_DIR}/Dockerfile" <<DOCKERFILE
FROM node:22-bookworm

RUN apt-get update && apt-get install -y socat && rm -rf /var/lib/apt/lists/*
${BINARY_LINES}

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
DOCKERFILE

# 6. Write .env
log "Writing .env…"
cat > "${REPO_DIR}/.env" <<ENVFILE
OPENCLAW_IMAGE=openclaw:latest
OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_PORT=${GATEWAY_PORT}

OPENCLAW_CONFIG_DIR=${HOME_DIR}/.openclaw
OPENCLAW_WORKSPACE_DIR=${HOME_DIR}/.openclaw/workspace

GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD}
XDG_CONFIG_HOME=/home/node/.openclaw
ENVFILE

# 7. Write docker-compose.yml
log "Writing docker-compose.yml…"
cat > "${REPO_DIR}/docker-compose.yml" <<'COMPOSEFILE'
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
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "${OPENCLAW_GATEWAY_BIND}",
        "--port",
        "${OPENCLAW_GATEWAY_PORT}",
      ]

  openclaw-cli:
    image: ${OPENCLAW_IMAGE}
    env_file:
      - .env
    environment:
      - HOME=/home/node
      - NODE_ENV=production
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD}
      - XDG_CONFIG_HOME=${XDG_CONFIG_HOME}
    volumes:
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    profiles: ["cli"]
COMPOSEFILE

chown -R "${OC_USER}:${OC_USER}" "${REPO_DIR}"

# 8. Build and launch
log "Building Docker image (this may take several minutes)…"
cd "$REPO_DIR"
sudo -u "$OC_USER" sg docker -c "docker compose build" 2>&1 | tail -5

log "Starting gateway…"
sudo -u "$OC_USER" sg docker -c "docker compose up -d openclaw-gateway"

# 9. Run setup and configure gateway
log "Running initial setup…"
sleep 5
sudo -u "$OC_USER" sg docker -c "docker compose stop openclaw-gateway"
sudo -u "$OC_USER" sg docker -c "docker compose run --rm openclaw-gateway node dist/index.js setup" || true

log "Configuring gateway mode and allowed origins…"
CONFIG_FILE="${HOME_DIR}/.openclaw/openclaw.json"
if [[ -f "$CONFIG_FILE" ]]; then
  python3 -c "
import json
with open('${CONFIG_FILE}', 'r') as f:
    config = json.load(f)
config.setdefault('gateway', {})['mode'] = 'local'
config['gateway'].setdefault('controlUi', {})['allowedOrigins'] = ['http://127.0.0.1:${GATEWAY_PORT}']
with open('${CONFIG_FILE}', 'w') as f:
    json.dump(config, f, indent=2)
"
fi

# 10. Fix file ownership and start
chown -R "${OC_USER}:${OC_USER}" "${HOME_DIR}/.openclaw/"
sudo -u "$OC_USER" sg docker -c "docker compose up -d openclaw-gateway"

touch "$MARKER"
log "OpenClaw Gateway provisioned and running."
