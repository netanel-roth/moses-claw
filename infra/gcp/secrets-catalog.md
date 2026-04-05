# GCP Secret Manager Catalog

Project: `moses-claw`
Region: global (automatic replication)
Service account with access: `openclaw-vm@moses-claw.iam.gserviceaccount.com`
Role: `roles/secretmanager.secretAccessor`

## Secrets

| Name | Purpose | Used by | Resolution method |
|---|---|---|---|
| `GROQ_API_KEY` | Whisper audio transcription | Groq plugin | env var via `.env.secrets` |
| `GEMINI_API_KEY` | Embeddings (planned) | Memory search | env var via `.env.secrets` |
| `TAVILY_API_KEY` | Web search | Tavily plugin | SecretRef in `openclaw.json` |
| `TELEGRAM_BOT_TOKEN` | Telegram bot auth | Telegram channel | SecretRef in `openclaw.json` |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway auth | Gateway internal | SecretRef + env var |
| `GOG_KEYRING_PASSWORD` | Keyring encryption | OpenClaw keyring | env var via `.env.secrets` |

## Access flow

1. VM boots → `openclaw-fetch-secrets.sh` runs (systemd unit or manual)
2. Script uses VM's service account to query Metadata API → gets OAuth token
3. Fetches secrets from GCP Secret Manager via REST API
4. Writes to `/home/openclaw/openclaw/.env.secrets` (chmod 600, owned by openclaw)
5. Docker compose loads `.env.secrets` into container env
6. OpenClaw gateway reads env vars + resolves SecretRefs via exec resolver

## Rotation procedure

```bash
# 1. Update secret in GCP Secret Manager
echo -n "NEW_VALUE" | gcloud secrets versions add SECRET_NAME --project=moses-claw --data-file=-

# 2. On VM: re-run fetch script
sudo /usr/local/bin/openclaw-fetch-secrets.sh

# 3. Restart gateway
cd /home/openclaw/openclaw
sudo -u openclaw sg docker -c "docker compose restart openclaw-gateway"
```

## Adding a new secret

```bash
# 1. Create secret
gcloud secrets create NEW_SECRET --project=moses-claw --replication-policy=automatic

# 2. Add version
echo -n "VALUE" | gcloud secrets versions add NEW_SECRET --project=moses-claw --data-file=-

# 3. Add to fetch script (if needed as env var)
# Edit /usr/local/bin/openclaw-fetch-secrets.sh, add: echo "NAME=$(fetch NEW_SECRET)"

# 4. Or use SecretRef in openclaw.json (if field supports it)
# See: docs/reference/secretref-credential-surface.md in OpenClaw repo
```
